class Reports

  require "./filters.rb"
  
  def self.friendly_filename( input_string )
    input_string.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
  end
  
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
  


  def self.session_details( clinic_sessions )
    # clinic_sessions = Analyze.extract_clinic_sessions( selected_entries )
    # dates = selected_entries.collect {|e| e["appt_at"]}
    # data_date_range = dates.min..dates.max
    #
    # squares = selected_entries.status_no_show.collect {|e| (1.0 - e[:prob_no_show]) ** 2 } +
    #   selected_entries.status_completed.collect {|e| (0.0 - e[:prob_no_show]) ** 2 }
    #
    # rms_error = Math.sqrt(squares.mean)

    
    
"""Clinic Session Details
Provider(s): #{  }
Report dates: #{  }



#{

    clinic_sessions.collect do |clinic_session|
        "#{ clinic_session[:id].gsub(/\|/, "  ") } / #{ (clinic_session[:encounters].status_completed + clinic_session[:encounters].status_no_show + clinic_session[:encounters].status_scheduled).sum_minutes / 60.0 } pt-hrs booked over #{ clinic_session[:hours_booked]} hrs\n" +

        clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.collect do |time, entries_for_time|
          entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} #{ e["Visit Type"]} (#{ e["Appt Status"]} #{e["Appt. Length"]}) #{ e["Total Amount"] } b#{ e["Appt. Booked on"]} c#{ e["Contact Date"]}" }.join(" / ")
          "    #{ time }  #{ entries_text }"
        end.join("\n")

    end.join("\n\n")
}
"""
  end

  
#
#   def self.sessions( selected_entries, clinic_sessions )
#     # entries_by_month = entries_all.group_by {|e| e["POST_MONTH"]}.sort_by {|m, t| "#{m}"}
#     dates = selected_entries.collect {|e| e["appt_at"]}
#     data_date_range = dates.min..dates.max
#
#     # report_months =
#
#     # =============================================================================
#     # =========================   timeslots analysis  =============================
#
#     goal_n_sessions_yr = 52 - 4
#     report_n_days = dates.max - dates.min
#     month_strings = data_date_range.to_a.collect {|e| e.strftime("%Y-%m") }.uniq
#     clinic_sessions_by_month = clinic_sessions.group_by {|e| e[:date].strftime("%Y-%m")}
#     month_strings.each do |month_string|
#        clinic_sessions_by_month[month_string] ||= []
#     end
#
#     clinic_sessions_by_month = clinic_sessions_by_month.sort_by {|m, es| m}
#
# """Sessions Report
# Provider(s): #{ selected_entries.providers.uniq.join(" / ") }
# Report dates: #{ data_date_range.min.strftime("%F") } - #{ data_date_range.max.strftime("%F") }
# Report generated: #{ Time.now.strftime("%F") }
#
# ===============================================================================
# ============================== Summary Report =================================
#
# 1. Clinic Sessions
# - Helps determine if you are on track
# - Full sessions are defined as half-days with 1.5 or more hours of patients booked
#
# #{
#   print_table([["Month", "Full sessions", "Partial sessions"]] +
#   clinic_sessions_by_month.collect {|month, entries_for_month|
#       [month,
#         entries_for_month.count {|e| !e[:is_partial_session] },
#         entries_for_month.count {|e| e[:is_partial_session] }
#       ]
#   } + [[
#     "SUM",
#     n_completed = clinic_sessions.count {|e| !e[:is_partial_session] },
#     n_partial = clinic_sessions.count {|e| e[:is_partial_session] }
#   ]])
# }
#
# ---
# Goal #{ (goal_n_sessions_yr / 365.0 * report_n_days ).round} complete sessions during this timeframe
#
#
# 2. Hours of patients booked for each clinic session
# - Booked refers to completed visits, no-shows, and scheduled visits
# - Over 4 hours represents overbooking
# - This may be thrown off by EMG and Botox sessions, because each patient is
#   listed for 15 minute slot
# #{
#   print_table([["Hrs", "historic", "future" ]] +
#     clinic_sessions.group_by {|e| e[:hours_booked] }.sort_by {|k,v| k}.select {|k,v| k > 0}.collect {|hours, entries|
#       [hours,
#         "|#{ self.progressbar( 1.0 * entries.past_sessions.size / clinic_sessions.size ) } (#{ entries.past_sessions.size })",
#         "|#{ self.progressbar( 1.0 * entries.future_sessions.size / clinic_sessions.size) } (#{ entries.future_sessions.size })",
#       ]
#     }
#  )
# }
#
#
# 3. Percent of timeslots booked, amongst full sessions
# - 100% booking is defined as 4 hours of patient care
# - Omits partial sessions (those with < 1.5 hrs of patients booked)
# - Cancellation does not count as a booked patient, even though late cancellations are
#   practically like no-shows
# - Method 1 counts the total minute-value of encounters where status is complete or
#   no-show, thus is susceptible to error if there are duplicate encounters, which
#   occurs in procedures
# - Method 2 counts percentage of 15-minute timeslots that are filled, therefore
#   cannot exceed 100% and does not give credit for doublebooked patients
#
# #{
#   complete_sessions = clinic_sessions.select {|e| !e[:is_partial_session] }
#
#   print_table([["Month", "% booked (patient-hours)", "% booked (timeslots filled)" ]] +
#   clinic_sessions_by_month.collect {|month, full_sessions_for_month|
#      x = full_sessions_for_month.select {|e| !e[:is_partial_session]}
#       num = x.collect {|e| e[:hours_booked]}.compact.sum
#       num2 = x.collect {|e| e[:visual].count(".") + e[:visual].count("X") + e[:visual].count("^")}.compact.sum * 0.25 # hours
#       denom = x.size * 4.0
#
#       [month,
#         self.progressbar( num / denom),
#         self.progressbar( num2 / denom)
#       ]
#   }
#   )
# }
#
# Overall  #{
#   total_num = complete_sessions.collect {|e| e[:hours_booked]}.compact.sum
#   total_denom = complete_sessions.size * 4.0
#
#   self.progressbar( total_num / total_denom)
# }
#
#
# 4. Cancelation with no rebooking, amongst full sessions
# - A fraction of the unbooked appointment slots used to have appointment until
#   cancelled.
# - Because this only includes full sessions, it takes into account that
#   occasionally, entire clinic sessions are cancelled by provider.
#
# #{
#   complete_sessions = clinic_sessions.select {|e| !e[:is_partial_session] and !e[:is_future_session]}
#
#   print_table([["Month", "Hours", "% of clinic timeslots" ]] +
#   clinic_sessions_by_month.collect {|month, full_sessions_for_month|
#
#       # count the number of Os which are each 15 min of cancellation-not-rebooked
#       num = full_sessions_for_month.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
#       denom = full_sessions_for_month.size * 4.0 # hours
#
#       [month,
#         num,
#         self.progressbar( (num / denom)),
#       ]
#   }
#   )
# }
#
# Overall  #{
#   num = complete_sessions.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
#   denom = complete_sessions.size * 4.0 # hours
#
#   self.progressbar( num / denom)
# }
#
#
# 5. Show rate (% Patients arrived, given booked)
# #{
#   print_table([["Month", "% showed" ]] +
#   clinic_sessions_by_month.collect {|month, sessions_for_month|
#       encounters_for_month = sessions_for_month.collect {|e| e[:encounters]}.flatten
#
#       n_show = encounters_for_month.status_completed.size
#       n_booked = encounters_for_month.status_no_show.size + n_show
#       [month,
#         self.progressbar( 1.0 * n_show / n_booked ),
#       ]
#   }
#   )
# }
#
# Overall  #{
#       encounters_for_month = clinic_sessions.collect {|e| e[:encounters]}.flatten
#
#       n_show = encounters_for_month.status_completed.size
#       n_booked = encounters_for_month.status_no_show.size + n_show
#
#       self.progressbar( 1.0 * n_show / n_booked )
# }
#
#
# 5. Clinic RVUs
# Jul   *** RVUs
# Aug   *** RVUs
# Sep   *** RVUs (*** YTD; Goal *** RVUs)
# ----
# Oct    expected *** RVUs (assuming same booking rate, same show rate)
# Nov    expected *** RVUs
# Dec    expected *** RVUs
# ---
# Projected entire FY 2017: *** RVUs (Goal *** RVUs)
#
#
# """
#
#
#   end


    
  def self.session_efficiency( selected_entries, clinic_sessions, **args )
    dates = selected_entries.collect {|e| e["appt_at"]}
    data_date_range = dates.min..dates.max
    args[:goal_hours_per_session] ||= 4
    

    # =============================================================================
    # =========================   timeslots analysis  =============================

    goal_n_sessions_yr = 52 - 4
    report_n_days = dates.max - dates.min

    # get a monthly grouping
    month_strings = data_date_range.to_a.collect {|e| e.strftime("%Y-%m") }.uniq
    clinic_sessions_by_month = clinic_sessions.group_by {|e| e[:date].strftime("%Y-%m")}
    month_strings.each do |month_string|
       clinic_sessions_by_month[month_string] ||= []
    end
    clinic_sessions_by_month = clinic_sessions_by_month.sort_by {|m, es| m}

    # calculate total booking percentage
    full_sessions = clinic_sessions.select {|e| !e[:is_partial_session] }
    total_num = full_sessions.collect {|e| e[:hours_booked]}.compact.sum
    total_denom = 1.0 * full_sessions.size * args[:goal_hours_per_session]
    total_booking_percentage = total_num / total_denom


    # calculate total show rate
    encounters_for_months = clinic_sessions.collect {|e| e[:encounters]}.flatten
    total_n_show = encounters_for_months.status_completed.size
    total_n_booked = encounters_for_months.status_no_show.size + total_n_show
    total_show_rate = (1.0 * total_n_show / total_n_booked)


    html do
       row do
          col(12) do 
             [
                h(3) {"Clinic Session Efficiency Report"},
                ul([
                   "Provider(s): #{ selected_entries.providers.uniq.join(" / ") }",
                   "Report dates: #{ data_date_range.min.strftime("%F") } - #{ data_date_range.max.strftime("%F") }",
                   "Report generated: #{ Time.now.strftime("%F") }"
               ]),
                   (total_booking_percentage.nan? or total_show_rate.nan?) ? "" : """
					
    					<hr />
    					<table style=\"margin-left: auto; margin-right: auto;\">
    						<tr>
    							<td><div class=\"lg-number\">#{ (total_booking_percentage * 100).round}%</div><p>Booking</p></td>
    							<td style=\"padding: 20px; \">&times;</td>
    							<td><div class=\"lg-number\">#{ (total_show_rate * 100).round }%</div><p>Show rate</p></td>
    							<td style=\"padding: 20px; \">=</td>
    							<td><div class=\"lg-number\">#{ (total_booking_percentage * total_show_rate * 100).round }%</div><p>Efficiency</p></td>
    						</tr>
    					</table>
                   """ ,
     					"<hr />",

                   """
<h3>1. Number of Clinic Sessions</h3>
<p>Helps determine if you are on track</p>
<div style=\"text-align:center; margin-bottom: 10px;\">
   Key 
   <span class=\"label label-info\">1</span> = AM session on the 1st of the month
   <span class=\"label label-primary\">1</span> = PM session
</div>
#{
table([["Month", "Full sessions", "Partial sessions (< 1.5hrs booked)"]] +
clinic_sessions_by_month.collect {|month, entries_for_month|
    [month,
      entries_for_month.select {|e| !e[:is_partial_session] }
         .collect {|e| "<span class=\"label label-#{ e[:am_pm] == "AM" ? "info" : "primary" }\">#{ e[:date].strftime("%-d") }</span>"}
         .join(" "),
      entries_for_month.select {|e| e[:is_partial_session] }
         .collect {|e| "<span class=\"label label-#{ e[:am_pm] == "AM" ? "info" : "primary" }\">#{ e[:date].strftime("%-d") }</span>"}
         .join(" ")
    ]
} + [[
  "SUM",
  n_completed = clinic_sessions.count {|e| !e[:is_partial_session] },
  n_partial = clinic_sessions.count {|e| e[:is_partial_session] }
]])
}

---



<h3>2. Hours of patients booked for each clinic session, histogram</h3>
Booked refers to completed visits, no-shows, and scheduled visits. This may be thrown off by EMG and Botox sessions, in which each patient is
listed for 15 minute slot.
#{
table([["Hrs of patients booked", "Number of sessions"]] +
  clinic_sessions.group_by {|e| e[:hours_booked] }.sort_by {|k,v| k}.select {|k,v| k > 0}.collect {|hours, entries|
    [(hours == args[:goal_hours_per_session] ? "#{ hours } (Goal)" : "#{ hours }"),
       
      "#{ progress( 1.0 * entries.select {|e| !e[:is_future_session]}.size / clinic_sessions.size, entries.select {|e| !e[:is_future_session]}.size ) }",
      # "#{ progress( 1.0 * entries.future_sessions.size / clinic_sessions.size, entries.future_sessions.size) }",
    ]
  }
)
}


<h3>3. Hours of patients booked for each clinic session, by month</h3>
Helps determine how saturated each clinic session is. This analysis omits 
partial sessions (those with < 1.5 hrs of patients booked). One limitation 
is that cancellation does not count as a booked patient here, even though 
late cancellations are practically like no-shows.

#{
full_sessions = clinic_sessions.select {|e| !e[:is_partial_session] }
total_num = full_sessions.collect {|e| e[:hours_booked]}.compact.sum
total_denom = 1.0 * full_sessions.size * args[:goal_hours_per_session]


table([["Month", "Hours booked", nil]] +
clinic_sessions_by_month.collect {|month, full_sessions_for_month|
   x = full_sessions_for_month.select {|e| !e[:is_partial_session]}
    num = x.collect {|e| e[:hours_booked]}.compact.sum
    num2 = x.collect {|e| e[:visual].count(".") + e[:visual].count("X") + e[:visual].count("^")}.compact.sum * 0.25 # hours
    denom = 1.0 * x.size * args[:goal_hours_per_session]
    hrs_method_1 = (1.0 * args[:goal_hours_per_session] * num / denom).round(1)
    hrs_method_2 = (1.0 * args[:goal_hours_per_session] * num2 / denom).round(1) 
    [month,
      progress( num / denom, hrs_method_1 ),
      (hrs_method_1 and hrs_method_2 and (hrs_method_1 != hrs_method_2)) ? "Ranges from #{hrs_method_2} to #{hrs_method_1} depending on method of calculation *" : ""  
    ]
} + [[ "Overall",
   progress( total_num / total_denom, (1.0 * args[:goal_hours_per_session] * total_num / total_denom).round(1)),
   nil
   ]]
)
}


<p>* Method 1 (graphed) counts the total minute-value of encounters where status is complete or
no-show, thus is susceptible to overcounting if there are duplicate encounters, which
occurs sometimes with procedures. Method 2 (shown if different from Method 1) counts unfilled timeslots, therefore
does not give credit for double-booked patients.</p>


<h3>4. Cancellation with no rebooking, amongst full sessions</h3>


#{
completed_full_sessions = clinic_sessions.select {|e| !e[:is_partial_session] and !e[:is_future_session]}

total_num = completed_full_sessions.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
total_denom = 1.0 * completed_full_sessions.size * args[:goal_hours_per_session] # hours

table([["Month", "Hours per clinic session" ]] +
clinic_sessions_by_month.collect {|month, full_sessions_for_month|

    # count the number of Os which are each 15 min of cancellation-not-rebooked
    num = full_sessions_for_month.collect {|e| e[:visual].count("O")}.compact.sum * 0.25 # hours
    denom = 1.0 * full_sessions_for_month.size * args[:goal_hours_per_session] # hours

    [month,
      progress( (num / denom), (1.0 * args[:goal_hours_per_session] * num / denom).round(1)),
    ]
} + [["Overall", progress( total_num / total_denom, (1.0 * args[:goal_hours_per_session] * total_num / total_denom).round(1)), nil ]]
)
}



<h3>5. Show rate (% Patients arrived, given booked)</h3>
#{
encounters_for_months = clinic_sessions.collect {|e| e[:encounters]}.flatten

total_n_show = encounters_for_months.status_completed.size
total_n_booked = encounters_for_months.status_no_show.size + total_n_show

# total_show_rate = (1.0 * total_n_show / total_n_booked)

table([["Month", "n showed", "% showed" ]] +
clinic_sessions_by_month.collect {|month, sessions_for_month|
    encounters_for_month = sessions_for_month.collect {|e| e[:encounters]}.flatten

    n_show = encounters_for_month.status_completed.size
    n_booked = encounters_for_month.status_no_show.size + n_show
    [month,
       "#{n_show} / #{n_booked}",
      progress( n_booked > 4 ? (1.0 * n_show / n_booked).round(2) : nil ),
    ]
} + [["Overall", "#{total_n_show} / #{total_n_booked}", progress( total_n_booked > 4 ? (1.0 * total_n_show / total_n_booked).round(2)  : nil) ]]
)
}

                   """
             ]
             
          end
       end
    end

  end

  def self.icon( name )
     "<span class=\"glyphicon glyphicon-#{ name }\" aria-hidden=\"true\"></span>"
  end
  
  def self.progress( frac, display_name = nil )
     pct = frac ? frac * 100 : frac
"""  <div class=\"progress\" style=\"margin-bottom: 0px; max-width: 220px; \" >
       <div class=\"progress-bar\" role=\"progressbar\" aria-valuenow=\"#{ pct }\" aria-valuemin=\"0\" aria-valuemax=\"100\" style=\"width: #{ pct }%;\">
         #{ display_name || "#{pct}%" }
       </div>
     </div>
"""
  end
  
  def self.table( arr )
	"<table class=\"table table-condensed\"><tbody>" + arr.collect do |sub_arr|
      "<tr>" + sub_arr.collect { |cell|
         "<t#{sub_arr == arr.first ? "h" : "d"}>#{ cell }</t#{sub_arr == arr.first ? "h" : "d"}>"
      }.join("") + "</tr>"
   end.join("") + "</tbody></table>"
  end
  
  
  def self.ul( arr )
     "<ul>" + arr.collect {|e| "<li>#{ e }</li>"}.join("") + "</ul>"
  end
  
  def self.h(n=1)
     """<h#{n}>#{ yield.class == Array ? yield.join("") : yield }</h#{ n }>"""
  end
  
  def self.row
     """<div class=\"row\">#{ yield.class == Array ? yield.join("") : yield }</div>"""
  end
  
  def self.col(n=12)
     """<div class=\"col-sm-#{ n }\">#{ yield.class == Array ? yield.join("") : yield }</div>"""
  end
  
  def self.html
"""
<html>
   <head>
   <!-- Latest compiled and minified CSS -->
   <link rel=\"stylesheet\" href=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css\" integrity=\"sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u\" crossorigin=\"anonymous\">

   <script
    src=\"https://code.jquery.com/jquery-3.2.1.min.js\"
    integrity=\"sha256-hwg4gsxgFZhOsEEamdOYGBf13FyQuiTwlAQgxVSNgt4=\"
    crossorigin=\"anonymous\"></script>

   <!-- Latest compiled and minified JavaScript -->
   <script src=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js\" integrity=\"sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa\" crossorigin=\"anonymous\"></script>	
   <link href=\"https://fonts.googleapis.com/css?family=Roboto:300,400\" rel=\"stylesheet\">

   <style type=\"text/css\" media=\"screen\">
   	.lg-number { font-size: 42pt; font-weight: 300; }
   	h1, h2, h3, h4, h5 { font-family: 'Roboto', sans-serif;}
   	body, p, li, td { font-size: 14px; font-family: 'Roboto', sans-serif; font-weight: 300;}
   </style>

   </head>
   <body>
   	<div class=\"container-fluid\">#{yield}</div><!-- /container -->
   </body>
</html>
"""
     
  end
end