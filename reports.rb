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
  

  def self.sessions( selected_entries, clinic_sessions )
    # entries_by_month = entries_all.group_by {|e| e["POST_MONTH"]}.sort_by {|m, t| "#{m}"}
    dates = selected_entries.collect {|e| e["appt_at"]}
    data_date_range = dates.min..dates.max
    
    # report_months = 
    
    # =============================================================================
    # =========================   timeslots analysis  =============================





    
"""
Sessions Report
Name:
Report dates: #{ data_date_range }

===============================================================================
============================== Summary Report =================================

1. Clinic Sessions
Complete sessions are defined as 2 hours or more of patients booked

#{
  print_table([["Month", "Complete sessions", "Partial sessions", "Scheduled sessions" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, entries_for_month|
      # complete_sessions
      # partial_sessions
      # scheduled_sessions
      [month, 
        entries_for_month.count {|e| e[:is_full_session] and !e[:is_future_session]}, 
        entries_for_month.count {|e| !e[:is_full_session] and !e[:is_future_session]}, 
        entries_for_month.count {|e| e[:is_future_session]}, 
      ]
  } + [[
    "SUM",
    clinic_sessions.count {|e| e[:is_full_session] and !e[:is_future_session]}, 
    clinic_sessions.count {|e| !e[:is_full_session] and !e[:is_future_session]}, 
    clinic_sessions.count {|e| e[:is_future_session]}, 
  ]])
}

---
Projected entire FY 2017: *** sessions (Goal *** sessions)


2. % Slots booked 
Defined as completed visits plus no-shows, divided by four hours per session

A histogram of how heavily booked each session is
#{
  print_table([["Hrs", "n prior sessions", "n future sessions" ]] +
    clinic_sessions.group_by {|e| e[:hours_booked] }.sort_by {|k,v| k}.select {|k,v| k > 0}.collect {|hours, entries|
      [hours, 
        "#{ entries.past_sessions.size.to_s.ljust(4, " ") } #{ "x" * entries.past_sessions.size }" ,
        entries.future_sessions.size
        
      ]
    }
 )
}


% Booking amongst the complete sessions (i.e. ignores sessions with <2hrs of patients)
Cancellation does not count as a booked patient

#{
  print_table([["Month", "% booked" ]] +
  clinic_sessions.group_by {|e| e[:date].strftime("%m/%Y")}.collect {|month, entries_for_month|
      # complete_sessions
      # partial_sessions
      # scheduled_sessions
      complete_sessions = entries_for_month.select {|e| e[:is_full_session]}  
      percent_booked_of_complete_sessions = complete_sessions.any? ? (complete_sessions.collect {|e| e[:hours_booked]}.compact.sum / ( complete_sessions.size * 4.0)) : nil
      [month, 
        self.progressbar( percent_booked_of_complete_sessions), 
      ]
  } 
  )
}

Overall  #{
  complete_sessions = clinic_sessions.select {|e| e[:is_full_session] and !e[:is_future_session]}  
  percent_booked_of_complete_sessions = complete_sessions.any? ? (complete_sessions.collect {|e| e[:hours_booked]}.compact.sum / ( complete_sessions.size * 4.0)) : nil
  
   
  self.progressbar( percent_booked_of_complete_sessions)
}
* booking rate for past sessions only (omits future sesions)


3. Percent of cancelled slots with a rebooking
***


4. Show rate (% Patients arrived, given booked)
#{
  print_table([["Month", "% booked" ]] +
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
    #
#
# 1. All encounters and procedures
# #{ print_table( [["MONTH", "n", "RVU", "PAYMTS"]] + entries_by_month.collect {|m,e| [
#   m,
#   (e - e.procedure_injection).sum_quantity,
#   e.sum_rvus,
#   "$#{ e.sum_payments }"
# ]})}
# * n excludes injections, however RVU includes injections
#
# Pct contribution to total payments
# Outpatient |#{ denom = entries_all.sum_payments;
#               progressbar( 1.0 * entries_all.outpatient.sum_payments / denom )}
# Inpatient  |#{ progressbar( 1.0 * entries_all.inpatient.sum_payments / denom )}
# Procedure  |#{ progressbar( 1.0 * entries_all.procedure.sum_payments / denom )}
#
#
# #{
#   has_codes = Hash[entries_all.positive_quantity.collect {|e| [e["PROC_CODE"], e["PROC_NAME"]] }.uniq]
#   codes_missing_rvus = has_codes.keys - Filters.rvu_map.keys
#
#   rows = codes_missing_rvus.collect {|e| "#{e}  #{has_codes[e]}"}
#
#   if rows.any?
#     (["Warning: RVUs counts may underestimate due to missing values for:"] + rows).join("\n")
#   else
#     nil
#   end
# }
#
#
# ===============================================================================
# ============================= Outpatient Report ===============================
#
# 1. All Outpatient Encounters
# #{ print_table( [["MONTH", "n", "RVU", "PAYMTS"]] + entries_by_month.collect {|m,e| [
#   m,
#   e.outpatient.sum_quantity,
#   e.outpatient.sum_rvus,
#   "$#{ e.outpatient.sum_payments }"
# ]})}
#
#
# 2. Pct of outpatient encounters that are initial (as opposed to followup)
# Benchmk|#{ benchmark( benchmark_stats[:outpt_frac_encounters_that_are_initial] ) } Division average, std dev
# #{ entries_by_month.collect { |m,e|
#   n_fup = e.outpatient_follow.sum_quantity
#   n_tot = e.outpatient.sum_quantity
#   frac_init = (n_tot > 0) ? (1.0 * (n_tot - n_fup) / n_tot) : nil
#
#   "#{m.ljust(7, " ")}|#{ progressbar(frac_init)}" }.join("\n") }
#
#
# 3. Pct Initial encounters billed as consult (as opposed to new)
# Benchmk|#{ benchmark( benchmark_stats[:outpt_frac_initial_that_are_consult] ) } Division average, std dev
# #{ entries_by_month.collect { |m,e|
#   n_new = e.outpatient_new.sum_quantity
#   n_cs = e.outpatient_consult.sum_quantity
#   frac_cs = (n_new + n_cs > 0) ? (1.0 * (n_cs) / (n_new + n_cs)) : nil
#
#   "#{m.ljust(7, " ")}|#{ progressbar(frac_cs)}" }.join("\n") }
#
#
# 4. Pct all outpatient encounters billed, by level:
# (Includes all types of outpatient encounters: consult, new, followup)
#
# #{ print_table(
#   [
#     ["Date", "n", "Level 4 & above", "Level 5"],
#     ["Benchmk", "-", "|#{ benchmark( benchmark_stats[:outpt_frac_level_4_and_up], true, 20 )}", "|#{ benchmark( benchmark_stats[:outpt_frac_level_5], true, 20)}"]
#   ] +
#   entries_by_month.collect { |m,e|
#   init = e.outpatient
#   l3 = init.level_3.sum_quantity
#   l4 = init.level_4.sum_quantity
#   l5 = init.level_5.sum_quantity
#
#   n_init = init.sum_quantity
#
#   [
#     m,
#     n_init,
#     n_init >= 5 ? "|#{progressbar(1.0 * (l4 + l5) / n_init, true, 20) }" : "| small sample",
#     n_init >= 5 ? "|#{progressbar(1.0 * l5 / n_init, true, 20) }" : "| small sample"
#   ]
# }
# )
# }
  end
end