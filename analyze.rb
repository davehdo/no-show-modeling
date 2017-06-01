module Analyze
  require "./filters.rb"
  
  
  def self.generate_odds_ratios_for_each_feature( encounters_no_show, encounters_completed )
    features_for_no_show = encounters_no_show.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}
    features_for_show = encounters_completed.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}

    n_show = encounters_completed.size
    n_no_show = encounters_no_show.size

    unique_feature_names = (features_for_show.keys + features_for_no_show.keys).uniq

    feature_statistics_array = unique_feature_names.collect {|feature_name|
      n_feature_and_show = (features_for_show[ feature_name ] || []).count {|k,v| v}
      n_feature_and_no_show = (features_for_no_show[ feature_name ] || []).count {|k,v| v}
  
  
      # var_odds_ratio = (var_p_feature_given_show * var_p_feature_given_no_show) +
      #   (var_p_feature_given_show * p_feature_given_no_show ** 2) +
      #   (var_p_feature_given_no_show * p_feature_given_show ** 2)

      # per md-calc
  
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