// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

//****************************************************************
// Function that controls aileron/rudder, elevator, rudder (if 4 channel control) and throttle to produce desired attitude and airspeed.
//****************************************************************


/*
  get a speed scaling number for control surfaces. This is applied to
  PIDs to change the scaling of the PID with speed. At high speed we
  move the surfaces less, and at low speeds we move them more.
 */
static float get_speed_scaler(void)
{
    float aspeed, speed_scaler;
    if (ahrs.airspeed_estimate(&aspeed)) {
        if (aspeed > 0) {
            speed_scaler = g.scaling_speed / aspeed;
        } else {
            speed_scaler = 2.0;
        }
        speed_scaler = constrain_float(speed_scaler, 0.5, 2.0);
    } else {
        if (channel_throttle->servo_out > 0) {
            speed_scaler = 0.5 + ((float)THROTTLE_CRUISE / channel_throttle->servo_out / 2.0);                 // First order taylor expansion of square root
            // Should maybe be to the 2/7 power, but we aren't goint to implement that...
        }else{
            speed_scaler = 1.67;
        }
        // This case is constrained tighter as we don't have real speed info
        speed_scaler = constrain_float(speed_scaler, 0.6, 1.67);
    }
    return speed_scaler;
}

/*
  return true if the current settings and mode should allow for stick mixing
 */
static bool stick_mixing_enabled(void)
{
    if (auto_throttle_mode) {
        // we're in an auto mode. Check the stick mixing flag
        if (g.stick_mixing != STICK_MIXING_DISABLED &&
            geofence_stickmixing() &&
            failsafe == FAILSAFE_NONE &&
            (g.throttle_fs_enabled == 0 || 
             channel_throttle->radio_in >= g.throttle_fs_value)) {
            // we're in an auto mode, and haven't triggered failsafe
            return true;
        } else {
            return false;
        }
    }
    // non-auto mode. Always do stick mixing
    return true;
}


/*
  this is the main roll stabilization function. It takes the
  previously set nav_roll calculates roll servo_out to try to
  stabilize the plane at the given roll
 */
static void stabilize_roll(float speed_scaler)
{
    if (inverted_flight) {
        // we want to fly upside down. We need to cope with wrap of
        // the roll_sensor interfering with wrap of nav_roll, which
        // would really confuse the PID code. The easiest way to
        // handle this is to ensure both go in the same direction from
        // zero
        nav_roll_cd += 18000;
        if (ahrs.roll_sensor < 0) nav_roll_cd -= 36000;
    }

    channel_roll->servo_out = g.rollController.get_servo_out(nav_roll_cd - ahrs.roll_sensor, 
                                                             speed_scaler, 
                                                             control_mode == STABILIZE, 
                                                             aparm.flybywire_airspeed_min);
}

/*
  this is the main pitch stabilization function. It takes the
  previously set nav_pitch and calculates servo_out values to try to
  stabilize the plane at the given attitude.
 */
static void stabilize_pitch(float speed_scaler)
{
    int32_t demanded_pitch = nav_pitch_cd + g.pitch_trim_cd + channel_throttle->servo_out * g.kff_throttle_to_pitch;
    channel_pitch->servo_out = g.pitchController.get_servo_out(demanded_pitch - ahrs.pitch_sensor, 
                                                               speed_scaler, 
                                                               control_mode == STABILIZE, 
                                                               aparm.flybywire_airspeed_min, 
                                                               aparm.flybywire_airspeed_max);    
}

/*
  this gives the user control of the aircraft in stabilization modes
 */
static void stabilize_stick_mixing_direct()
{
    if (!stick_mixing_enabled() ||
        control_mode == ACRO ||
        control_mode == FLY_BY_WIRE_A ||
        control_mode == FLY_BY_WIRE_B ||
        control_mode == CRUISE ||
        control_mode == TRAINING) {
        return;
    }
    // do direct stick mixing on aileron/elevator
    float ch1_inf;
    float ch2_inf;
        
    ch1_inf = (float)channel_roll->radio_in - (float)channel_roll->radio_trim;
    ch1_inf = fabsf(ch1_inf);
    ch1_inf = min(ch1_inf, 400.0);
    ch1_inf = ((400.0 - ch1_inf) /400.0);
        
    ch2_inf = (float)channel_pitch->radio_in - channel_pitch->radio_trim;
    ch2_inf = fabsf(ch2_inf);
    ch2_inf = min(ch2_inf, 400.0);
    ch2_inf = ((400.0 - ch2_inf) /400.0);
        
    // scale the sensor input based on the stick input
    // -----------------------------------------------
    channel_roll->servo_out  *= ch1_inf;
    channel_pitch->servo_out *= ch2_inf;
    
    // Mix in stick inputs
    // -------------------
    channel_roll->servo_out  +=     channel_roll->pwm_to_angle();
    channel_pitch->servo_out +=    channel_pitch->pwm_to_angle();
}

/*
  this gives the user control of the aircraft in stabilization modes
  using FBW style controls
 */
static void stabilize_stick_mixing_fbw()
{
    if (!stick_mixing_enabled() ||
        control_mode == ACRO ||
        control_mode == FLY_BY_WIRE_A ||
        control_mode == FLY_BY_WIRE_B ||
        control_mode == CRUISE ||
        control_mode == TRAINING) {
        return;
    }
    // do FBW style stick mixing. We don't treat it linearly
    // however. For inputs up to half the maximum, we use linear
    // addition to the nav_roll and nav_pitch. Above that it goes
    // non-linear and ends up as 2x the maximum, to ensure that
    // the user can direct the plane in any direction with stick
    // mixing.
    float roll_input = channel_roll->norm_input();
    if (roll_input > 0.5f) {
        roll_input = (3*roll_input - 1);
    } else if (roll_input < -0.5f) {
        roll_input = (3*roll_input + 1);
    }
    nav_roll_cd += roll_input * g.roll_limit_cd;
    nav_roll_cd = constrain_int32(nav_roll_cd, -g.roll_limit_cd.get(), g.roll_limit_cd.get());
    
    float pitch_input = channel_pitch->norm_input();
    if (fabsf(pitch_input) > 0.5f) {
        pitch_input = (3*pitch_input - 1);
    }
    if (inverted_flight) {
        pitch_input = -pitch_input;
    }
    if (pitch_input > 0) {
        nav_pitch_cd += pitch_input * aparm.pitch_limit_max_cd;
    } else {
        nav_pitch_cd += -(pitch_input * aparm.pitch_limit_min_cd);
    }
    nav_pitch_cd = constrain_int32(nav_pitch_cd, aparm.pitch_limit_min_cd.get(), aparm.pitch_limit_max_cd.get());
}


/*
  stabilize the yaw axis
 */
static void stabilize_yaw(float speed_scaler)
{
    float ch4_inf = 1.0;

    if (stick_mixing_enabled()) {
        // stick mixing performed for rudder for all cases including FBW
        // important for steering on the ground during landing
        // -----------------------------------------------
        ch4_inf = (float)channel_rudder->radio_in - (float)channel_rudder->radio_trim;
        ch4_inf = fabsf(ch4_inf);
        ch4_inf = min(ch4_inf, 400.0);
        ch4_inf = ((400.0 - ch4_inf) /400.0);
    }

    // Apply output to Rudder
    calc_nav_yaw(speed_scaler, ch4_inf);
    channel_rudder->servo_out *= ch4_inf;
    channel_rudder->servo_out += channel_rudder->pwm_to_angle();
}


/*
  a special stabilization function for training mode
 */
static void stabilize_training(float speed_scaler)
{
    if (training_manual_roll) {
        channel_roll->servo_out = channel_roll->control_in;
    } else {
        // calculate what is needed to hold
        stabilize_roll(speed_scaler);
        if ((nav_roll_cd > 0 && channel_roll->control_in < channel_roll->servo_out) ||
            (nav_roll_cd < 0 && channel_roll->control_in > channel_roll->servo_out)) {
            // allow user to get out of the roll
            channel_roll->servo_out = channel_roll->control_in;            
        }
    }

    if (training_manual_pitch) {
        channel_pitch->servo_out = channel_pitch->control_in;
    } else {
        stabilize_pitch(speed_scaler);
        if ((nav_pitch_cd > 0 && channel_pitch->control_in < channel_pitch->servo_out) ||
            (nav_pitch_cd < 0 && channel_pitch->control_in > channel_pitch->servo_out)) {
            // allow user to get back to level
            channel_pitch->servo_out = channel_pitch->control_in;            
        }
    }

    stabilize_yaw(speed_scaler);
}


/*
  this is the ACRO mode stabilization function. It does rate
  stabilization on roll and pitch axes
 */
static void stabilize_acro(float speed_scaler)
{
    float roll_rate = (channel_roll->control_in/4500.0f) * g.acro_roll_rate;
    float pitch_rate = (channel_pitch->control_in/4500.0f) * g.acro_pitch_rate;

    /*
      check for special roll handling near the pitch poles
     */
    if (roll_rate == 0) {
        /*
          we have no roll stick input, so we will enter "roll locked"
          mode, and hold the roll we had when the stick was released
         */
        if (!acro_state.locked_roll) {
            acro_state.locked_roll = true;
            acro_state.locked_roll_err = 0;
        } else {
            acro_state.locked_roll_err += ahrs.get_gyro().x * 0.02f;
        }
        int32_t roll_error_cd = -ToDeg(acro_state.locked_roll_err)*100;
        nav_roll_cd = ahrs.roll_sensor + roll_error_cd;
        // try to reduce the integrated angular error to zero. We set
        // 'stabilze' to true, which disables the roll integrator
        channel_roll->servo_out  = g.rollController.get_servo_out(roll_error_cd,
                                                                  speed_scaler,
                                                                  true,
                                                                  aparm.flybywire_airspeed_min);
    } else {
        /*
          aileron stick is non-zero, use pure rate control until the
          user releases the stick
         */
        acro_state.locked_roll = false;
        channel_roll->servo_out  = g.rollController.get_rate_out(roll_rate,  speed_scaler);
    }

    if (pitch_rate == 0) {
        /*
          user has zero pitch stick input, so we lock pitch at the
          point they release the stick
         */
        if (!acro_state.locked_pitch) {
            acro_state.locked_pitch = true;
            acro_state.locked_pitch_cd = ahrs.pitch_sensor;
        }
        // try to hold the locked pitch. Note that we have the pitch
        // integrator enabled, which helps with inverted flight
        nav_pitch_cd = acro_state.locked_pitch_cd;
        channel_pitch->servo_out  = g.pitchController.get_servo_out(nav_pitch_cd - ahrs.pitch_sensor,
                                                                    speed_scaler,
                                                                    false,
                                                                    aparm.flybywire_airspeed_min,
                                                                    aparm.flybywire_airspeed_max);
    } else {
        /*
          user has non-zero pitch input, use a pure rate controller
         */
        acro_state.locked_pitch = false;
        channel_pitch->servo_out = g.pitchController.get_rate_out(pitch_rate, speed_scaler);
    }

    /*
      call the normal yaw stabilize for now. This allows for manual
      rudder input, plus automatic coordinated turn handling. For
      knife-edge we'll need to do something quite different
     */
    stabilize_yaw(speed_scaler);
}

/*
  main stabilization function for all 3 axes
 */
static void stabilize()
{
    if (control_mode == MANUAL) {
        // nothing to do
        return;
    }
    float speed_scaler = get_speed_scaler();

    if (control_mode == TRAINING) {
        stabilize_training(speed_scaler);
    } else if (control_mode == ACRO) {
        stabilize_acro(speed_scaler);
    } else {
        if (g.stick_mixing == STICK_MIXING_FBW && control_mode != STABILIZE) {
            stabilize_stick_mixing_fbw();
        }
        stabilize_roll(speed_scaler);
        stabilize_pitch(speed_scaler);
        if (g.stick_mixing == STICK_MIXING_DIRECT || control_mode == STABILIZE) {
            stabilize_stick_mixing_direct();
        }
        stabilize_yaw(speed_scaler);
    }

    /*
      see if we should zero the attitude controller integrators. 
     */
    if (channel_throttle->control_in == 0 &&
        relative_altitude_abs_cm() < 500 && 
        fabs(barometer.get_climb_rate()) < 0.5f &&
        g_gps->ground_speed_cm < 300) {
        // we are low, with no climb rate, and zero throttle, and very
        // low ground speed. Zero the attitude controller
        // integrators. This prevents integrator buildup pre-takeoff.
        g.rollController.reset_I();
        g.pitchController.reset_I();
        g.yawController.reset_I();
    }
}


static void calc_throttle()
{
    if (aparm.throttle_cruise <= 1) {
        // user has asked for zero throttle - this may be done by a
        // mission which wants to turn off the engine for a parachute
        // landing
        channel_throttle->servo_out = 0;
        return;
    }

    if (g.alt_control_algorithm == ALT_CONTROL_TECS || g.alt_control_algorithm == ALT_CONTROL_DEFAULT) {
        channel_throttle->servo_out = SpdHgt_Controller->get_throttle_demand();
    } else if (!alt_control_airspeed()) {
        int16_t throttle_target = aparm.throttle_cruise + throttle_nudge;

        // TODO: think up an elegant way to bump throttle when
        // groundspeed_undershoot > 0 in the no airspeed sensor case; PID
        // control?

        // no airspeed sensor, we use nav pitch to determine the proper throttle output
        // AUTO, RTL, etc
        // ---------------------------------------------------------------------------
        if (nav_pitch_cd >= 0) {
            channel_throttle->servo_out = throttle_target + (aparm.throttle_max - throttle_target) * nav_pitch_cd / aparm.pitch_limit_max_cd;
        } else {
            channel_throttle->servo_out = throttle_target - (throttle_target - aparm.throttle_min) * nav_pitch_cd / aparm.pitch_limit_min_cd;
        }

        channel_throttle->servo_out = constrain_int16(channel_throttle->servo_out, aparm.throttle_min.get(), aparm.throttle_max.get());
    } else {
        // throttle control with airspeed compensation
        // -------------------------------------------
        energy_error = airspeed_energy_error + altitude_error_cm * 0.098f;

        // positive energy errors make the throttle go higher
        channel_throttle->servo_out = aparm.throttle_cruise + g.pidTeThrottle.get_pid(energy_error);
        channel_throttle->servo_out += (channel_pitch->servo_out * g.kff_pitch_to_throttle);

        channel_throttle->servo_out = constrain_int16(channel_throttle->servo_out,
                                                       aparm.throttle_min.get(), aparm.throttle_max.get());
    }


}

/*****************************************
* Calculate desired roll/pitch/yaw angles (in medium freq loop)
*****************************************/

//  Yaw is separated into a function for heading hold on rolling take-off
// ----------------------------------------------------------------------
static void calc_nav_yaw(float speed_scaler, float ch4_inf)
{
    if (hold_course_cd != -1) {
        // steering on or close to ground
        int32_t bearing_error_cd = nav_controller->bearing_error_cd();
        channel_rudder->servo_out = g.pidWheelSteer.get_pid_4500(bearing_error_cd, speed_scaler) + 
            g.kff_rudder_mix * channel_roll->servo_out;
        channel_rudder->servo_out = constrain_int16(channel_rudder->servo_out, -4500, 4500);
        return;
    }

    channel_rudder->servo_out = g.yawController.get_servo_out(speed_scaler, 
                                                              control_mode == STABILIZE, 
                                                              aparm.flybywire_airspeed_min, 
                                                              aparm.flybywire_airspeed_max);

    // add in rudder mixing from roll
    channel_rudder->servo_out += channel_roll->servo_out * g.kff_rudder_mix;
    channel_rudder->servo_out = constrain_int16(channel_rudder->servo_out, -4500, 4500);
}


static void calc_nav_pitch()
{
    // Calculate the Pitch of the plane
    // --------------------------------
    if (g.alt_control_algorithm == ALT_CONTROL_TECS || g.alt_control_algorithm == ALT_CONTROL_DEFAULT) {
        nav_pitch_cd = SpdHgt_Controller->get_pitch_demand();
    } else if (alt_control_airspeed()) {
        nav_pitch_cd = -g.pidNavPitchAirspeed.get_pid(airspeed_error_cm);
    } else {
        nav_pitch_cd = g.pidNavPitchAltitude.get_pid(altitude_error_cm);
    }
    nav_pitch_cd = constrain_int32(nav_pitch_cd, aparm.pitch_limit_min_cd.get(), aparm.pitch_limit_max_cd.get());
}


static void calc_nav_roll()
{
    nav_roll_cd = nav_controller->nav_roll_cd();
    nav_roll_cd = constrain_int32(nav_roll_cd, -g.roll_limit_cd.get(), g.roll_limit_cd.get());
}


/*****************************************
* Roll servo slew limit
*****************************************/
/*
 *  float roll_slew_limit(float servo)
 *  {
 *       static float last;
 *       float temp = constrain_float(servo, last-ROLL_SLEW_LIMIT * delta_ms_fast_loop/1000.f, last + ROLL_SLEW_LIMIT * delta_ms_fast_loop/1000.f);
 *       last = servo;
 *       return temp;
 *  }*/

/*****************************************
* Throttle slew limit
*****************************************/
static void throttle_slew_limit(int16_t last_throttle)
{
    // if slew limit rate is set to zero then do not slew limit
    if (aparm.throttle_slewrate) {                   
        // limit throttle change by the given percentage per second
        float temp = aparm.throttle_slewrate * G_Dt * 0.01 * fabsf(channel_throttle->radio_max - channel_throttle->radio_min);
        // allow a minimum change of 1 PWM per cycle
        if (temp < 1) {
            temp = 1;
        }
        channel_throttle->radio_out = constrain_int16(channel_throttle->radio_out, last_throttle - temp, last_throttle + temp);
    }
}


/*
  check for automatic takeoff conditions being met
 */
static bool auto_takeoff_check(void)
{
#if 1
    if (g_gps == NULL || g_gps->status() != GPS::GPS_OK_FIX_3D) {
        // no auto takeoff without GPS lock
        return false;
    }
    if (g_gps->ground_speed_cm < g.takeoff_throttle_min_speed*100.0f) {
        // we haven't reached the minimum ground speed
        return false;
    }

    if (g.takeoff_throttle_min_accel > 0.0f) {
        float xaccel = ins.get_accel().x;
        if (ahrs.pitch_sensor > -3000 && 
            ahrs.pitch_sensor < 4500 &&
            abs(ahrs.roll_sensor) < 3000 && 
            xaccel >= g.takeoff_throttle_min_accel) {
            // trigger with minimum acceleration when flat
            // Thanks to Chris Miser for this suggestion
            gcs_send_text_fmt(PSTR("Triggered AUTO xaccel=%.1f"), xaccel);
            return true;
        }
        return false;
    }

    // we're good for takeoff
    return true;

#else
    // this is a more advanced check that relies on TECS
    uint32_t now = hal.scheduler->micros();
    static bool launchCountStarted;
    static uint32_t last_tkoff_arm_time;

    if (g_gps == NULL || g_gps->status() != GPS::GPS_OK_FIX_3D) 
    {
        // no auto takeoff without GPS lock
        return false;
    }
    if (SpdHgt_Controller->get_VXdot() >= g.takeoff_throttle_min_accel || g.takeoff_throttle_min_accel == 0.0 || launchCountStarted)
    {
        if (!launchCountStarted) 
        {
		launchCountStarted = true;
        last_tkoff_arm_time = now;
        gcs_send_text_fmt(PSTR("Armed AUTO, xaccel = %.1f m/s/s, waiting %.1f sec"), SpdHgt_Controller->get_VXdot(), 0.1f*float(min(g.takeoff_throttle_delay,15)));
        }
 		if ((now - last_tkoff_arm_time) <= 2500000)
		{
            
			if ((g_gps->ground_speed > g.takeoff_throttle_min_speed*100.0f || g.takeoff_throttle_min_speed == 0.0) && ((now -last_tkoff_arm_time) >= min(uint32_t(g.takeoff_throttle_delay*100000),1500000)))
            {
                gcs_send_text_fmt(PSTR("Triggered AUTO, GPSspd = %.1f"), g_gps->ground_speed*100.0f);
			    launchCountStarted = false;
		        last_tkoff_arm_time = 0;
			    return true;
		    }
		    else
			{
 			    launchCountStarted = true;
 			    return false;
            }
        }
        else
        {
            gcs_send_text_fmt(PSTR("Timeout AUTO"));
		    launchCountStarted = false;
		    last_tkoff_arm_time = 0;
	    	return false;
        }
    }         
    launchCountStarted = false;
	last_tkoff_arm_time = 0;
    return false;
#endif
}


/* We want to supress the throttle if we think we are on the ground and in an autopilot controlled throttle mode.

   Disable throttle if following conditions are met:
   *       1 - We are in Circle mode (which we use for short term failsafe), or in FBW-B or higher
   *       AND
   *       2 - Our reported altitude is within 10 meters of the home altitude.
   *       3 - Our reported speed is under 5 meters per second.
   *       4 - We are not performing a takeoff in Auto mode or takeoff speed/accel not yet reached
   *       OR
   *       5 - Home location is not set
*/
static bool suppress_throttle(void)
{
    if (!throttle_suppressed) {
        // we've previously met a condition for unsupressing the throttle
        return false;
    }
    if (!auto_throttle_mode) {
        // the user controls the throttle
        throttle_suppressed = false;
        return false;
    }

    if (control_mode==AUTO && takeoff_complete == false && auto_takeoff_check()) {
        // we're in auto takeoff 
        throttle_suppressed = false;
        if (hold_course_cd != -1) {
            // update takeoff course hold, if already initialised
            hold_course_cd = ahrs.yaw_sensor;
            gcs_send_text_fmt(PSTR("Holding course %ld"), hold_course_cd);
        }
        return false;
    }
    
    if (relative_altitude_abs_cm() >= 1000) {
        // we're more than 10m from the home altitude
        throttle_suppressed = false;
        return false;
    }

    if (g_gps != NULL && 
        g_gps->status() >= GPS::GPS_OK_FIX_2D && 
        g_gps->ground_speed_cm >= 500) {
        // if we have an airspeed sensor, then check it too, and
        // require 5m/s. This prevents throttle up due to spiky GPS
        // groundspeed with bad GPS reception
        if (!airspeed.use() || airspeed.get_airspeed() >= 5) {
            // we're moving at more than 5 m/s
            throttle_suppressed = false;
            return false;        
        }
    }

    // throttle remains suppressed
    return true;
}

/*
  implement a software VTail or elevon mixer. There are 4 different mixing modes
 */
static void channel_output_mixer(uint8_t mixing_type, int16_t &chan1_out, int16_t &chan2_out)
{
    int16_t c1, c2;
    int16_t v1, v2;

    // first get desired elevator and rudder as -500..500 values
    c1 = chan1_out - 1500;
    c2 = chan2_out - 1500;

    v1 = (c1 - c2) * g.mixing_gain;
    v2 = (c1 + c2) * g.mixing_gain;

    // now map to mixed output
    switch (mixing_type) {
    case MIXING_DISABLED:
        return;

    case MIXING_UPUP:
        break;

    case MIXING_UPDN:
        v2 = -v2;
        break;

    case MIXING_DNUP:
        v1 = -v1;
        break;

    case MIXING_DNDN:
        v1 = -v1;
        v2 = -v2;
        break;
    }

    // scale for a 1500 center and 900..2100 range, symmetric
    v1 = constrain_int16(v1, -600, 600);
    v2 = constrain_int16(v2, -600, 600);

    chan1_out = 1500 + v1;
    chan2_out = 1500 + v2;
}

/*****************************************
* Set the flight control servos based on the current calculated values
*****************************************/
static void set_servos(void)
{
    int16_t last_throttle = channel_throttle->radio_out;

    if (control_mode == MANUAL) {
        // do a direct pass through of radio values
        if (g.mix_mode == 0 || g.elevon_output != MIXING_DISABLED) {
            channel_roll->radio_out                = channel_roll->radio_in;
            channel_pitch->radio_out               = channel_pitch->radio_in;
        } else {
            channel_roll->radio_out                = channel_roll->read();
            channel_pitch->radio_out               = channel_pitch->read();
        }
        channel_throttle->radio_out    = channel_throttle->radio_in;
        channel_rudder->radio_out              = channel_rudder->radio_in;

        // setup extra channels. We want this to come from the
        // main input channel, but using the 2nd channels dead
        // zone, reverse and min/max settings. We need to use
        // pwm_to_angle_dz() to ensure we don't trim the value for the
        // deadzone of the main aileron channel, otherwise the 2nd
        // aileron won't quite follow the first one
        RC_Channel_aux::set_servo_out(RC_Channel_aux::k_aileron, channel_roll->pwm_to_angle_dz(0));
        RC_Channel_aux::set_servo_out(RC_Channel_aux::k_elevator, channel_pitch->pwm_to_angle_dz(0));
        RC_Channel_aux::set_servo_out(RC_Channel_aux::k_rudder, channel_rudder->pwm_to_angle_dz(0));

        // this variant assumes you have the corresponding
        // input channel setup in your transmitter for manual control
        // of the 2nd aileron
        RC_Channel_aux::copy_radio_in_out(RC_Channel_aux::k_aileron_with_input);
        RC_Channel_aux::copy_radio_in_out(RC_Channel_aux::k_elevator_with_input);
        RC_Channel_aux::copy_radio_in_out(RC_Channel_aux::k_flap_auto);

        if (g.mix_mode == 0 && g.elevon_output == MIXING_DISABLED) {
            // set any differential spoilers to follow the elevons in
            // manual mode. 
            RC_Channel_aux::set_radio(RC_Channel_aux::k_dspoiler1, channel_roll->radio_out);
            RC_Channel_aux::set_radio(RC_Channel_aux::k_dspoiler2, channel_pitch->radio_out);
        }
    } else {
        if (g.mix_mode == 0) {
            // both types of secondary aileron are slaved to the roll servo out
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_aileron, channel_roll->servo_out);
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_aileron_with_input, channel_roll->servo_out);

            // both types of secondary elevator are slaved to the pitch servo out
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_elevator, channel_pitch->servo_out);
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_elevator_with_input, channel_pitch->servo_out);

            // setup secondary rudder
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_rudder, channel_rudder->servo_out);
        }else{
            /*Elevon mode*/
            float ch1;
            float ch2;
            ch1 = channel_pitch->servo_out - (BOOL_TO_SIGN(g.reverse_elevons) * channel_roll->servo_out);
            ch2 = channel_pitch->servo_out + (BOOL_TO_SIGN(g.reverse_elevons) * channel_roll->servo_out);

			/* Differential Spoilers
               If differential spoilers are setup, then we translate
               rudder control into splitting of the two ailerons on
               the side of the aircraft where we want to induce
               additional drag.
             */
			if (RC_Channel_aux::function_assigned(RC_Channel_aux::k_dspoiler1) && RC_Channel_aux::function_assigned(RC_Channel_aux::k_dspoiler2)) {
				float ch3 = ch1;
				float ch4 = ch2;
				if ( BOOL_TO_SIGN(g.reverse_elevons) * channel_rudder->servo_out < 0) {
				    ch1 += abs(channel_rudder->servo_out);
				    ch3 -= abs(channel_rudder->servo_out);
				} else {
					ch2 += abs(channel_rudder->servo_out);
				    ch4 -= abs(channel_rudder->servo_out);
				}
				RC_Channel_aux::set_servo_out(RC_Channel_aux::k_dspoiler1, ch3);
				RC_Channel_aux::set_servo_out(RC_Channel_aux::k_dspoiler2, ch4);
			}

            // directly set the radio_out values for elevon mode
            channel_roll->radio_out  =     elevon.trim1 + (BOOL_TO_SIGN(g.reverse_ch1_elevon) * (ch1 * 500.0/ SERVO_MAX));
            channel_pitch->radio_out =     elevon.trim2 + (BOOL_TO_SIGN(g.reverse_ch2_elevon) * (ch2 * 500.0/ SERVO_MAX));
        }

#if OBC_FAILSAFE == ENABLED
        // this is to allow the failsafe module to deliberately crash 
        // the plane. Only used in extreme circumstances to meet the
        // OBC rules
        if (obc.crash_plane()) {
            channel_roll->servo_out = -4500;
            channel_pitch->servo_out = -4500;
            channel_rudder->servo_out = -4500;
            channel_throttle->servo_out = 0;
        }
#endif
        

        // push out the PWM values
        if (g.mix_mode == 0) {
            channel_roll->calc_pwm();
            channel_pitch->calc_pwm();
        }
        channel_rudder->calc_pwm();

#if THROTTLE_OUT == 0
        channel_throttle->servo_out = 0;
#else
        // convert 0 to 100% into PWM
        channel_throttle->servo_out = constrain_int16(channel_throttle->servo_out, 
                                                       aparm.throttle_min.get(), 
                                                       aparm.throttle_max.get());

        if (suppress_throttle()) {
            // throttle is suppressed in auto mode
            channel_throttle->servo_out = 0;
            if (g.throttle_suppress_manual) {
                // manual pass through of throttle while throttle is suppressed
                channel_throttle->radio_out = channel_throttle->radio_in;
            } else {
                channel_throttle->calc_pwm();                
            }
        } else if (g.throttle_passthru_stabilize && 
                   (control_mode == STABILIZE || 
                    control_mode == TRAINING ||
                    control_mode == ACRO ||
                    control_mode == FLY_BY_WIRE_A)) {
            // manual pass through of throttle while in FBWA or
            // STABILIZE mode with THR_PASS_STAB set
            channel_throttle->radio_out = channel_throttle->radio_in;
        } else {
            // normal throttle calculation based on servo_out
            channel_throttle->calc_pwm();
        }
#endif
    }

    // Auto flap deployment
    if(control_mode < FLY_BY_WIRE_B) {
        RC_Channel_aux::copy_radio_in_out(RC_Channel_aux::k_flap_auto);
    } else if (control_mode >= FLY_BY_WIRE_B) {
        int16_t flapSpeedSource = 0;

        // FIXME: use target_airspeed in both FBW_B and g.airspeed_enabled cases - Doug?
        if (control_mode == FLY_BY_WIRE_B) {
            flapSpeedSource = target_airspeed_cm * 0.01;
        } else if (airspeed.use()) {
            flapSpeedSource = g.airspeed_cruise_cm * 0.01;
        } else {
            flapSpeedSource = aparm.throttle_cruise;
        }
        if ( g.flap_1_speed != 0 && flapSpeedSource > g.flap_1_speed) {
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_flap_auto, 0);
        } else if (g.flap_2_speed != 0 && flapSpeedSource > g.flap_2_speed) {
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_flap_auto, g.flap_1_percent);
        } else {
            RC_Channel_aux::set_servo_out(RC_Channel_aux::k_flap_auto, g.flap_2_percent);
        }
    }

    if (control_mode >= FLY_BY_WIRE_B) {
        /* only do throttle slew limiting in modes where throttle
         *  control is automatic */
        throttle_slew_limit(last_throttle);
    }

    if (control_mode == TRAINING) {
        // copy rudder in training mode
        channel_rudder->radio_out   = channel_rudder->radio_in;
    }

#if HIL_MODE != HIL_MODE_DISABLED
    if (!g.hil_servos) {
        return;
    }
#endif

    if (g.vtail_output != MIXING_DISABLED) {
        channel_output_mixer(g.vtail_output, channel_pitch->radio_out, channel_rudder->radio_out);
    } else if (g.elevon_output != MIXING_DISABLED) {
        channel_output_mixer(g.elevon_output, channel_pitch->radio_out, channel_roll->radio_out);
    }

    // send values to the PWM timers for output
    // ----------------------------------------
    channel_roll->output();
    channel_pitch->output();
    channel_throttle->output();
    channel_rudder->output();
    // Route configurable aux. functions to their respective servos
    g.rc_5.output_ch(CH_5);
    g.rc_6.output_ch(CH_6);
    g.rc_7.output_ch(CH_7);
    g.rc_8.output_ch(CH_8);
 #if CONFIG_HAL_BOARD == HAL_BOARD_PX4
    g.rc_9.output_ch(CH_9);
 #endif
 #if CONFIG_HAL_BOARD == HAL_BOARD_APM2 || CONFIG_HAL_BOARD == HAL_BOARD_PX4
    g.rc_10.output_ch(CH_10);
    g.rc_11.output_ch(CH_11);
 #endif
 #if CONFIG_HAL_BOARD == HAL_BOARD_PX4
    g.rc_12.output_ch(CH_12);
 # endif
}

static bool demoing_servos;

static void demo_servos(uint8_t i) 
{
    while(i > 0) {
        gcs_send_text_P(SEVERITY_LOW,PSTR("Demo Servos!"));
        demoing_servos = true;
        servo_write(1, 1400);
        mavlink_delay(400);
        servo_write(1, 1600);
        mavlink_delay(200);
        servo_write(1, 1500);
        demoing_servos = false;
        mavlink_delay(400);
        i--;
    }
}

// return true if we should use airspeed for altitude/throttle control
static bool alt_control_airspeed(void)
{
    return airspeed.use() && g.alt_control_algorithm == ALT_CONTROL_AIRSPEED;
}
