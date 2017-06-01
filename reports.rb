class Reports

  require "./filters.rb"
  
  def self.progressbar(fraction, label = true, size = 35, char = "x")
    statistics = {mean: fraction}
    
    chart = (" " * size) + ((label and statistics[:mean] != nil and !statistics[:mean].nan?) ? "  #{ (100.0 * statistics[:mean]).round }%" : "").ljust(6, " ")

    if statistics[:mean] != nil and !statistics[:mean].nan?
      n_blocks_to_fill = (1.0 * statistics[:mean] * size).round
      if n_blocks_to_fill <= 0
        # do nothing
      elsif n_blocks_to_fill > size
        chart[0...size] = char * size
      else
        chart[0...n_blocks_to_fill] = char * n_blocks_to_fill 
      end
    elsif chart.size >= 7
      chart[0...7] = "no data"
    end
    
    chart
    
  end

  def self.benchmark(statistics = {}, label = true, size = 35)
    # statistics = {
    #     mean: mean,
    #     var: var,
    #     n: n,
    #     stderr: stderr
    #   }
    statistics ||= {}
    chart = (" " * size) + ((label and statistics[:mean] != nil and !statistics[:mean].nan?) ? "  #{ (100.0 * statistics[:mean]).round }%" : "").ljust(6, " ")
    
    if statistics[:upper] != nil and statistics[:lower] != nil and !statistics[:upper].nan? and !statistics[:lower].nan? 
      upper_i = (1.0 * statistics[:upper] * size).floor
      lower_i = (1.0 * statistics[:lower] * size).floor
    
      upper_i = (size - 1) if upper_i > size - 1
      lower_i = (size - 1) if lower_i > size - 1
      upper_i = 0 if upper_i < 0
      lower_i = 0 if lower_i < 0
    
      chart[lower_i..upper_i] = "=" * (upper_i - lower_i + 1) if lower_i <= upper_i
    end

    if statistics[:mean] != nil
      mean_i = (1.0 * statistics[:mean] * size).floor
      
      mean_i = (size - 1) if mean_i > size - 1
      chart[mean_i] = "*"
    end
    
    if statistics[:upper] != nil and statistics[:lower] != nil and !statistics[:upper].nan? and !statistics[:lower].nan? 
    
      chart[lower_i] = "|"
      chart[upper_i] = "|"
    end
    # self.progressbar( statistics[:mean], label, size, "=")
    chart
  end


  # this table print adapts the column widths to the longest item in each column
  def self.print_table( array_of_arrays )
    x = array_of_arrays.transpose
    lengths = x.collect {|y| y.collect {|z| z.to_s.length}.max + 2 }
    
    array_of_arrays.collect do |ary|
      l = lengths.clone
    
      ary.collect {|e| e.to_s.ljust( l.shift, " ")}.join
    end.join("\n")
  end
  
  def self.print_table_with_dimension_and_metrics( entries_all, dimension_name_1 )
    headings = [["n", "sum_quantity"], ["RVU", "sum_rvus"], ["PAYMT", "sum_payments"], ["nProc", "procedure.sum_quantity"]]
    
    print_table( [[dimension_name_1] + headings.collect {|k,v| k} ] + entries_all.group_by {|e| e[dimension_name_1]}
      .sort_by {|m, t| "#{m}"}
      .collect {|m,e| [m] + headings.collect {|k,v| v.split('.').inject(e, :send)} })

  end
  
  
  def self.sessions_prediction(selected_entries, clinic_sessions)
    # clinic_sessions = Analyze.extract_clinic_sessions( selected_entries )
    dates = selected_entries.collect {|e| e["appt_at"]}
    data_date_range = dates.min..dates.max
    
    squares = selected_entries.status_no_show.collect {|e| (1.0 - e[:prob_no_show]) ** 2 } + 
      selected_entries.status_completed.collect {|e| (0.0 - e[:prob_no_show]) ** 2 }

    rms_error = Math.sqrt(squares.mean)

    
    
"""No-show Prediction Report
Provider(s): #{ selected_entries.providers.uniq.join(" / ") }
Report dates: #{ data_date_range.min.strftime("%F") } - #{ data_date_range.max.strftime("%F") }

Validation was performed at RMS error of #{ rms_error }

#{

    clinic_sessions.select {|e| e[:is_future_session]}.collect do |clinic_session|
        "#{ clinic_session[:id] } / #{ clinic_session[:encounters].status_completed.sum_minutes } / #{ clinic_session[:hours_booked]} hb / #{ clinic_session[:visual] } / #{ (clinic_session[:visual].count(".") + clinic_session[:visual].count("X")) * 0.25}\n" +

        clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.collect do |time, entries_for_time|
          entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} #{ e["Visit Type"]} (#{ e["Appt Status"]} #{e["Appt. Length"]}) #{ "#{(e[:prob_no_show] * 100).round}%" if e["Appt Status"]=="Scheduled"}" }.join(" / ")
          "    #{ time }  #{ entries_text }"
        end.join("\n")

    end.join("\n")
}
"""
  end
  
  
  def self.sessions( selected_entries, clinic_sessions )
    # entries_by_month = entries_all.group_by {|e| e["POST_MONTH"]}.sort_by {|m, t| "#{m}"}
    dates = selected_entries.collect {|e| e["appt_at"]}
    data_date_range = dates.min..dates.max
    
    # report_months = 
    
    # =============================================================================
    # =========================   timeslots analysis  =============================





    
"""
Sessions Report
Provider(s): #{ selected_entries.providers.uniq.join(" / ") }
Report dates: #{ data_date_range.min.strftime("%F") } - #{ data_date_range.max.strftime("%F") }

===============================================================================
============================== Summary Report =================================

1. Clinic Sessions
- Helps determine if you are on track
- Full sessions are defined as half-days with 2 or more hours of patients booked

#{
  print_table([["Month", "Full sessions", "Partial sessions", "Scheduled sessions" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, entries_for_month|
      [month, 
        entries_for_month.count {|e| e[:is_full_session] and !e[:is_future_session]}, 
        entries_for_month.count {|e| !e[:is_full_session] and !e[:is_future_session]}, 
        entries_for_month.count {|e| e[:is_future_session]}, 
      ]
  } + [[
    "SUM",
    n_completed = clinic_sessions.count {|e| e[:is_full_session] and !e[:is_future_session]}, 
    n_partial = clinic_sessions.count {|e| !e[:is_full_session] and !e[:is_future_session]}, 
    n_scheduled = clinic_sessions.count {|e| e[:is_future_session]}, 
  ]])
}

---
Projected entire FY 2017: #{n_completed + n_scheduled} sessions (Goal *** sessions)


2. Hours of patients booked for each clinic session
- Booked refers to completed visits, no-shows, and scheduled visits
- Over 4 hours represents overbooking
- This may be thrown off by EMG and Botox sessions, because each patient is 
  listed for 15 minute slot
#{
  print_table([["Hrs", "historic", "future" ]] +
    clinic_sessions.group_by {|e| e[:hours_booked] }.sort_by {|k,v| k}.select {|k,v| k > 0}.collect {|hours, entries|
      [hours, 
        "|#{ self.progressbar( 1.0 * entries.past_sessions.size / clinic_sessions.size ) } (#{ entries.past_sessions.size })",
        "|#{ self.progressbar( 1.0 * entries.future_sessions.size / clinic_sessions.size) } (#{ entries.future_sessions.size })",        
      ]
    }
 )
}


3. Percent of timeslots booked, amongst full sessions 
- Full sessions are defined as half-days with 2 or more hours of patients booked
- 100% booking is defined as 4 hours of patient care
- Omits sessions with <2hrs of patients
- Cancellation does not count as a booked patient, even though late cancellations are 
  practically like no-shows
- Method 1 counts the total minute-value of encounters where status is complete or 
  no-show, thus is susceptible to error if there are duplicate encounters, which 
  occurs in procedures
- Method 2 counts percentage of 15-minute timeslots that are filled, therefore 
  cannot exceed 100% and does not give credit for doublebooked patients
 
#{
  complete_sessions = clinic_sessions.select {|e| e[:is_full_session] and !e[:is_future_session]}  
  
  print_table([["Month", "% booked (method 1)", "% booked (method 2)" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, full_sessions_for_month|

      num = full_sessions_for_month.collect {|e| e[:hours_booked]}.compact.sum
      num2 = full_sessions_for_month.collect {|e| e[:visual].count(".") + e[:visual].count("X")}.compact.sum * 0.25 # hours
      denom = full_sessions_for_month.size * 4.0

      [month, 
        self.progressbar( num / denom), 
        self.progressbar( num2 / denom), 
      ]
  } 
  )
}

Overall  #{
  num = complete_sessions.collect {|e| e[:hours_booked]}.compact.sum
  denom = complete_sessions.size * 4.0
  
  self.progressbar( num / denom)
}



4. Cancelation with no rebooking, amongst full sessions
- A fraction of the unbooked appointment slots used to have appointment until 
  cancelled. 
- Because this only includes full sessions, it takes into account that 
  occasionally, entire clinic sessions are cancelled by provider.

#{
  complete_sessions = clinic_sessions.select {|e| e[:is_full_session] and !e[:is_future_session]}  

  print_table([["Month", "Hours", "% of clinic time" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, full_sessions_for_month|

      # count the number of Os which are each 15 min of cancellation-not-rebooked
      num = full_sessions_for_month.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
      denom = full_sessions_for_month.size * 4.0 # hours

      [month, 
        num,
        self.progressbar( (num / denom)), 
      ]
  } 
  )
}

Overall  #{
  num = complete_sessions.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
  denom = complete_sessions.size * 4.0 # hours
   
  self.progressbar( num / denom)
}


5. Show rate (% Patients arrived, given booked)
#{
  print_table([["Month", "% showed" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, sessions_for_month|
      encounters_for_month = sessions_for_month.collect {|e| e[:encounters]}.flatten
      
      n_show = encounters_for_month.status_completed.size
      n_booked = encounters_for_month.status_no_show.size + n_show
      [month, 
        self.progressbar( 1.0 * n_show / n_booked ), 
      ]
  } 
  )
}

Overall  #{
      encounters_for_month = clinic_sessions.collect {|e| e[:encounters]}.flatten
    
      n_show = encounters_for_month.status_completed.size
      n_booked = encounters_for_month.status_no_show.size + n_show

      self.progressbar( 1.0 * n_show / n_booked )
} 


5. Clinic RVUs
Jul	*** RVUs
Aug	*** RVUs
Sep	*** RVUs (*** YTD; Goal *** RVUs)
----
Oct 	expected *** RVUs (assuming same booking rate, same show rate)
Nov 	expected *** RVUs
Dec 	expected *** RVUs
---
Projected entire FY 2017: *** RVUs (Goal *** RVUs)


"""


  end
end