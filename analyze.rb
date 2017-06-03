module Analyze
  require "./filters.rb"
  
  def self.categorize_continuous_variable_log( var=nil, base=10, digits=1, min=nil, max=nil)
    if var and var > 0
      rounded = (base ** Math.log(var, base).floor)
      if max != nil and rounded >= max
        ">=#{ max }"
      elsif min != nil and rounded < min
        "<=#{ min }"
      else
        rounded.to_s.rjust( digits , "0")
      end
    else
      nil
    end
  end
  
  def self.categorize_continuous_variable( var=nil, base=10, digits=1, min=nil, max=nil)
    if var and var > 0
      rounded = (1.0 * base * (1.0 * var / base).floor).to_i
      if max != nil and rounded >= max
        ">=#{ max }"
      elsif min != nil and rounded < min
        "<=#{ min }"
      else
        rounded.to_s.rjust( digits , "0")
      end
    else
      nil
    end
  end
  
  
  def self.assign_odds_ratios( encounters_all, log_odds_ratios_by_feature, outcome_stored_as)  
    puts "\nAssigning probabilities to encounters based on their features (#{ log_odds_ratios_by_feature.size } are meaningful)"

    pretest_prob = 1.0 * encounters_all.status_no_show.size / ( encounters_all.status_no_show.size + encounters_all.status_completed.size)
  
    puts "  using a pretest probability of #{ pretest_prob }"
    encounters_all.each {|e| 

      e[:log_odds_ratios_itemized] = e["features"].collect {|feature_name,val|
        [feature_name, val, log_odds_ratios_by_feature[feature_name]]
      }.select {|f| f[2] != nil and f[1] != nil}
      sum_log_odds = e[:log_odds_ratios_itemized].collect {|f| 1.0 * f[1] * f[2]}.sum || 0.0
      
      e[:odds_ratio_no_show] = Math.exp( sum_log_odds )
      pretest_odds = pretest_prob / (1 - pretest_prob)
      posttest_odds = e[:odds_ratio_no_show] * pretest_odds 
      e[outcome_stored_as] = posttest_odds / (1 + posttest_odds)
    }
  end


  
  
  def self.validate_model( test_no_show, test_show, outcome_stored_as)
    squares = test_no_show.collect {|e| (1.0 - e[outcome_stored_as]) ** 2 } + 
      test_show.collect {|e| (0.0 - e[outcome_stored_as]) ** 2 }

    rms_error = Math.sqrt(squares.mean)
    puts "  A validation was performed at RMS error of:  #{ rms_error }"
    rms_error
  end
  
  
  def self.assign_multiple_regression( encounters_all, multiple_regression_model, outcome_stored_as)
    # e.g. Equation=-1.411 + -0.018appt_hour_09 + 0.009appt_hour_10 + -0.139appt_hour_12 + -0.014appt_hour_13 + -0.088appt_hour_14 + 0.144appt_hour_15 + -0.057appt_type_botox injection + 0.264appt_type_procedure + 0.103appt_type_return patient visit + 0.379dept_neurodiagnostics_pmuc + -0.165dept_neurology_hup + -0.059dept_neurology_pah + 0.052dept_neurology_pmuc + 0.102dept_neurology_ppmc_305_medical_office_bldg + -0.168dept_neurology_south_pavilion + -0.000dist_km + -0.002prior_cancellations_past_2yr + 0.325prior_no_show_past_2yr + -0.078prior_show_past_2yr
    
    log_odds_ratios_by_feature = multiple_regression_model.coeffs
    puts "  Assigning probabilities to encounters based on their features (#{ log_odds_ratios_by_feature.size } are meaningful)"
        
    # puts "  using a pretest probability of #{ pretest_prob }"
    encounters_all.each {|e| 
      e[:log_odds_ratios_itemized] = e["features"].collect {|feature_name,val|
        [feature_name, val, log_odds_ratios_by_feature[feature_name]]
      }.select {|f| f[2] != nil and f[1] != nil}
  
      sum_log_odds = (e[:log_odds_ratios_itemized].collect {|f| 1.0 * f[1] * f[2]}.sum || 0.0) + multiple_regression_model.constant

      posttest_odds = Math.exp( sum_log_odds ) 
      e[outcome_stored_as] = posttest_odds / (1 + posttest_odds)
    }
  end


  def self.train_multiple_regression( encounters_no_show, encounters_completed )
    puts "Running multiple regression "
    features_for_no_show = encounters_no_show.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}
    features_for_show = encounters_completed.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}

    n_show = encounters_completed.size
    n_no_show = encounters_no_show.size

    unique_feature_names = (features_for_show.keys + features_for_no_show.keys).uniq

    # multiple regression example
    ds = {}
    
    puts "  Assembling arrays for #{ unique_feature_names.size } predictors"
    unique_feature_names.each do |feature_name|
      arr = (encounters_no_show + encounters_completed ).collect {|e| e["features"][feature_name] || 0}
      
      # we keep only the features that have decent predictive value, 
      # as calcuated by an odds ratio.
      # This helps reduce the computational requirement for training
      # and reduces that chance that "Regressors are linearly dependent"
      n_feature_and_show = (features_for_show[ feature_name ] || []).count {|k,v| v != 0}
      n_feature_and_no_show = (features_for_no_show[ feature_name ] || []).count {|k,v| v != 0}

      a = n_feature_and_no_show # exposed, bad outcome
      c = n_no_show - n_feature_and_no_show # control, bad outcome
      b = n_feature_and_show # exposed, good outcome
      d = n_show - n_feature_and_show # control, good outcome
  
      odds_ratio = 1.0 * a * d / ( b * c)
      
      log_odds_ratio = Math.log( odds_ratio ) # base e
      se_log_odds_ratio = Math.sqrt( (1.0 / a) + (1.0 / b) + (1.0 / c) + (1.0 / d)) 
            
      lower = Math.exp(log_odds_ratio - 1.28 * se_log_odds_ratio )
      upper = Math.exp(log_odds_ratio + 1.28 * se_log_odds_ratio )
                
      ds[feature_name] = arr.to_vector(:scale) if lower > 1.0 or upper < 1.0
    end
  
    puts "  Assembling array of training outcomes"
    # we use 10 and -10 as log odds
    ds["no-show"] = (encounters_no_show.collect {2.0} + encounters_completed.collect {-2.0}).to_vector(:scale)
    
    puts "  Training the model"
    lr=Statsample::Regression.multiple(ds.to_dataset,'no-show')
  end  

  
  
  def self.train_odds_ratios( encounters_no_show, encounters_completed )
    features_for_no_show = encounters_no_show.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}
    features_for_show = encounters_completed.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}

    n_show = encounters_completed.size
    n_no_show = encounters_no_show.size

    unique_feature_names = (features_for_show.keys + features_for_no_show.keys).uniq

    feature_statistics_array = unique_feature_names.collect {|feature_name|
      n_feature_and_show = (features_for_show[ feature_name ] || []).count {|k,v| v == 1}
      n_feature_and_no_show = (features_for_no_show[ feature_name ] || []).count {|k,v| v == 1}
  
  
      # var_odds_ratio = (var_p_feature_given_show * var_p_feature_given_no_show) +
      #   (var_p_feature_given_show * p_feature_given_no_show ** 2) +
      #   (var_p_feature_given_no_show * p_feature_given_show ** 2)

      # per md-calc https://www.medcalc.org/calc/odds_ratio.php
  
      a = n_feature_and_no_show # exposed, bad outcome
      c = n_no_show - n_feature_and_no_show # control, bad outcome
      b = n_feature_and_show # exposed, good outcome
      d = n_show - n_feature_and_show # control, good outcome
  
      odds_ratio = 1.0 * a * d / ( b * c)

      log_odds_ratio = Math.log( odds_ratio ) # base e
      se_log_odds_ratio = Math.sqrt( (1.0 / a) + (1.0 / b) + (1.0 / c) + (1.0 / d)) 

      # significant = ((odds_ratio_lower > 1.0) or ( odds_ratio_upper < 1.0))
      {
        feature_name: feature_name,
        odds_ratio_of_no_show: odds_ratio,
        or_95_ci_lower: Math.exp(log_odds_ratio - 1.96 * se_log_odds_ratio ),
        or_95_ci_upper: Math.exp(log_odds_ratio + 1.96 * se_log_odds_ratio ),
        n_feature_and_show: n_feature_and_show,
        n_feature_and_no_show: n_feature_and_no_show,
        n_show: n_show,
        n_no_show: n_no_show,
        log_odds_ratio: log_odds_ratio,
        se_log_odds_ratio: se_log_odds_ratio,
        or_80_ci_lower: Math.exp(log_odds_ratio - 1.28 * se_log_odds_ratio ),
        or_80_ci_upper: Math.exp(log_odds_ratio + 1.28 * se_log_odds_ratio ),
        # significant: significant
      } 
    }.sort_by {|e| e[:feature_name]}
      
  end
  
    
  def self.extract_clinic_sessions( encounters )
    clinic_sessions = encounters.group_by {|e| e["clinic_session"]}.collect {|session_id, encounters_in_session|
  
      parts = session_id.split("|") # [provider, date, am/pm]
      start_hour = parts[2] == "AM" ? 8 : 13
      start_time = DateTime.new(2017, 1, 1, start_hour, 0, 0)
      timeslots = ( 0...(4 * 60)).step(15).collect {|interval|
        "#{parts[0]}|#{parts[1]}|#{ (start_time + interval / 24.0 / 60.0).strftime("%H:%M") }"
      }
  
  
      timeslots_completed = encounters_in_session.status_completed.collect {|e| e["timeslots"] }.flatten.uniq
      timeslots_no_show = encounters_in_session.status_no_show.collect {|e| e["timeslots"] }.flatten.uniq
      timeslots_cancelled = encounters_in_session.status_cancelled.collect {|e| e["timeslots"] }.flatten.uniq
      timeslots_scheduled = encounters_in_session.status_scheduled.collect {|e| e["timeslots"] }.flatten.uniq
      timeslots_other = encounters_in_session.collect {|e| e["timeslots"] }.flatten.uniq - 
      timeslots_scheduled - timeslots_completed - timeslots_no_show - timeslots_cancelled
    
      visual = timeslots.collect {|timeslot|
        if timeslots_completed.include?( timeslot )
          "." # completed
        elsif timeslots_no_show.include?( timeslot )
          "X" # no show
        elsif timeslots_cancelled.include?( timeslot )
          "O" # cancellation, not filled
        elsif timeslots_scheduled.include?( timeslot )
          "^"
        elsif timeslots_other.include?( timeslot )
          "?" # other
        else
          " "
        end
      }.join("")

  
      {
        id: session_id, 
        timeslots: timeslots,
        provider: parts[0],
        date: Date.parse( parts[1] ),
        am_pm: parts[2],
        encounters: encounters_in_session,
        hours_booked: (encounters_in_session.status_completed + encounters_in_session.status_no_show + encounters_in_session.status_scheduled).sum_minutes / 60.0,
        hours_completed: (encounters_in_session.status_completed ).sum_minutes / 60.0,
        is_full_session: (encounters_in_session.status_completed + encounters_in_session.status_no_show + encounters_in_session.status_scheduled).sum_minutes >= 120,
        is_future_session: (encounters_in_session.status_scheduled ).sum_minutes >= 30,
        visual: visual,
      }
    }
  end

end