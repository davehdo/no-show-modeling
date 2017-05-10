# this script analyzes billing reports
# Report is calling “Charges, Payments and Adjustments”
# exported from business objects… (PROMIS)


require "csv"
require "./filters.rb"
require "./reports.rb"
# require 'yaml'
# require "./billing_stats.rb"


# =============================================================================
# ==========================  load the billing data  ==========================
input_file = "neurologyvisits-2017-05-includes-cancelled.csv"
# provider_groupings_filename = "provider_groupings.csv"
# assistant_provider_groupings_filename = "assistant_provider_groupings.csv"
# stats_outpatient_filename = "stats_outpatient_divisions.yml"
# stats_inpatient_filename = "stats_inpatient_divisions.yml"
# provider_grouping_template_filename = "provider_groupings_template.csv"
# assistant_provider_grouping_template_filename = "assistant_provider_groupings_template.csv"


puts "Loading data file #{ input_file }"
@encounters_all = CSV.read(input_file, {headers: true})

puts "  loaded; there are #{ @encounters_all.size} rows"


# =============================================================================
# ============================   fix timestamps   =============================
timeslot_size = 15

@encounters_all.each {|e| 
  e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
  e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
  e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
  e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
  
  # e.g. timeslot   KIMBARIS, GRACE CHEN|2014-09-18|13:15
  e["timeslots"] = (0...(e["Appt. Length"].to_i)).step(timeslot_size).collect {|interval| 
    timeslot = e["appt_at"] + (interval / 24.0 / 60.0)
    "#{ e["Provider"]}|#{ timeslot.strftime("%F|%H:%M") }"  
  }
  
  puts "Warning: #{ e["Appt. Length"] } min appt but #{ e["timeslots"].size } timeslots (#{e["timeslots"]})" if (1.0 * e["Appt. Length"].to_i / timeslot_size).to_i != e["timeslots"].size
}

# "CSN":"95834500 " "Patient Name":"DOE,JOHN" "MRN":"012345589" "Age at Encounter":"60 " "Gender":"Male" "Ethnicity":"Non-Hispanic Non-Latino" "Race":"White" "Contact Date":" 01/16/2015" "Zip Code":"11111" "Appt. Booked on":"2014-10-17" "Appt. Time":" 01/16/2015  15:30 " "Checkin Time":" 01/16/2015  14:22 " "Appt Status":"Completed" "Referring Provider":"TORMENTI, MATTHEW J" "Department":"NEUROLOGY HUP" "Department ID":"378 " "Department Specialty":"Neurology" "Visit Type":"NEW PATIENT VISIT" "Procedure Category":"New Patient Visit" "Patient Class":"MAPS" "Provider":"RUBENSTEIN, MICHAEL NEIL" "Appt. Length":"60 " "Total Amount":"265.00"

# Visit Type
# ["NEW PATIENT VISIT", "RETURN PATIENT VISIT", "EMG", "PROCEDURE", "BOTOX INJECTION", "LUMBAR PUNCTURE", "RESEARCH", "RETURN PATIENT TELEMEDICINE", "NEW PATIENT SICK", "ALLIED HEALTH NON CHARGEABLE", "EEG ROUTINE", "LABORATORY", "ESTABLISHED PATIENT SPECIALTY", "NEW PATIENT TELEMEDICINE", "INDEPENDENT MEDICAL EXAM"]

# Procedure Category
# ["New Patient Visit", "Return Patient Visit", "Office Procedure", "Research", nil]

# Appt Status
# ["Completed", "Canceled", "No Show", "Left without seen", "Arrived", "Scheduled"]


# Characteristics of the data
# sometimes there is identical patient in a slot twice, one cancelled, and one completed

# Patient Class
# ["MAPS", "Outpatient", nil, "Family Accounts", "OFFICE VISITS", "AM Admit"]



# =============================================================================
# ==============================   check data  ================================
# # e.g. 16:00  X,MARYANNE (Completed) / X,MARYANNE (Canceled) / X,JULIANNE (Canceled)
# @encounters_all.group_by {|e| "#{e["appt_at"].iso8601}" }.each {|timeslot, e|
#   if e.status_completed.size > 1
#     puts "Warning: multiple completed appointments at #{ timeslot }"
#   end
# }.flatten


# 2014-07-01T08:00 to 2017-04-28T16:30

# puts appt_times.min.inspect
# puts appt_times.max.inspect
# puts DateTime.strptime(appt_times.min, ' %m/%d/%Y  %H:%M ').inspect
# raise @encounters_all.collect {|e| e["Patient Class"]}.uniq.inspect

# =============================================================================
# =========================   inspect encounters  =============================

def extract_clinic_sessions( encounters )
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
    timeslots_other = encounters_in_session.collect {|e| e["timeslots"] }.flatten.uniq - timeslots_completed - timeslots_no_show - timeslots_cancelled

    visual = timeslots.collect {|timeslot|
      if timeslots_completed.include?( timeslot )
        "." # completed
      elsif timeslots_no_show.include?( timeslot )
        "X" # no show
      elsif timeslots_cancelled.include?( timeslot )
        "O" # cancellation, not filled
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
      hours_booked: (encounters_in_session.status_completed + encounters_in_session.status_no_show).sum_minutes / 60.0,
      hours_completed: (encounters_in_session.status_completed ).sum_minutes / 60.0,
      is_full_session: (encounters_in_session.status_completed + encounters_in_session.status_no_show).sum_minutes > 120,
      visual: visual,
    }
  }
end


selected_entries = @encounters_all.select {|e| e["Provider"] == "RUBENSTEIN, MICHAEL NEIL"}
  .select {|e| e["appt_at"] > DateTime.new(2016, 1, 1) and e["appt_at"] < DateTime.new(2016, 7, 1)}
  .sort_by {|e| e["appt_at"]}




clinic_sessions = extract_clinic_sessions( selected_entries )

clinic_sessions.each do |clinic_session|
    puts "=== Session: #{clinic_session[:visual]} #{ clinic_session[:id] } === #{ clinic_session[:encounters].status_completed.sum_minutes }"
    
    clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.each do |time, entries_for_time|
      entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} (#{ e["Appt Status"]})" }.join(" / ")
      puts "    #{ time }  #{ entries_text }"
    end
        
end



# timeslots_cancelled_with_no_replacement = (timeslots_cancelled - timeslots_no_show - timeslots_completed)
#
# encounters_cancelled_with_no_replacement = timeslots_cancelled_with_no_replacement.collect do |timeslot|
#   selected_entries.select {|e| e["timeslots"].include?(timeslot) }
# end.flatten
#
# puts "=== cancelled_with_no_replacement"
# encounters_cancelled_with_no_replacement.each do |e|
#   puts "#{ e["contacted_on"] } - #{ e["appt_at"] } = #{ (e["appt_at"] - e["contacted_on"]).to_f.round(1) } days notice of cancellation"
# end
#
# puts "=== cancelled_with_replacement"
# (selected_entries.status_cancelled - encounters_cancelled_with_no_replacement).each do |e|
#   puts "#{ e["contacted_on"] } - #{ e["appt_at"] } = #{ (e["appt_at"] - e["contacted_on"]).to_f.round(1) } days notice of cancellation"
# end


# selected_entries.status_cancelled.each do |e|
#
# end

# =============================================================================
# =======================  output a table of providers  =======================

# # File.open("provider_groupings_template.csv", 'w') do |file|
# #   file.write(.uniq.join("\n") )
# # end
# puts "Generating provider list and saving as --#{ provider_grouping_template_filename }--"
# CSV.open("#{ provider_grouping_template_filename }", "wb") do |csv|
#   csv << ["PROV_NAME", "RVU_INPATIENT", "RVU_OUTPATIENT", "RVU_PROCEDURES",
#     "GENERATE_REPORT", "OUTPATIENT_GROUP", "INCLUDE_IN_INPATIENT_STATS",
#     "INPATIENT_GROUP", "INCLUDE_IN_OUTPATIENT_STATS" ]
#   @billing_data_all.group_by {|e| e["PROV_NAME"]}.each do |prov_name, e|
#     csv << [prov_name, e.inpatient.sum_quantity, e.outpatient.sum_quantity,
#       e.procedure.sum_quantity, false, nil, true, nil, true]
#   end
# end
#
# # =============================================================================
# # ==============  output a table of ASSISTANT providers  ======================
# # SERV_PROV_NAME
#
# puts "Generating provider list and saving as --#{ assistant_provider_grouping_template_filename }--"
#
# list_of_primary_providers = @billing_data_all.collect {|e| e["PROV_NAME"]}.uniq
#
# CSV.open("#{ assistant_provider_grouping_template_filename }", "wb") do |csv|
#   csv << ["SERV_PROV_NAME", "RVU_INPATIENT", "RVU_OUTPATIENT", "RVU_PROCEDURES",
#     "GENERATE_REPORT", "OUTPATIENT_GROUP", "INCLUDE_IN_INPATIENT_STATS",
#     "INPATIENT_GROUP", "INCLUDE_IN_OUTPATIENT_STATS" ]
#   @billing_data_all.group_by {|e| e["SERV_PROV_NAME"]}
#     .select {|k,v| !list_of_primary_providers.include?(k)}
#     .each do |prov_name, e|
#     csv << [prov_name, e.inpatient.sum_quantity, e.outpatient.sum_quantity,
#       e.procedure.sum_quantity, false, nil, true, nil, true]
#   end
# end
#
#
# # =============================================================================
# # ===================  check if list-of-providers exists  =====================
#
# if File.file?(provider_groupings_filename)
#   @provider_groupings = CSV.read(provider_groupings_filename, {headers: true})
# else
#   raise "Please copy the automatically-generated --#{ provider_grouping_template_filename  }--
#     to --#{provider_groupings_filename}--, and modify columns to select patients to generate reports"
# end
#
# if File.file?(assistant_provider_groupings_filename)
#   @assistant_provider_groupings = CSV.read(assistant_provider_groupings_filename, {headers: true})
# else
#   raise "Please copy the automatically-generated --#{ assistant_provider_grouping_template_filename }--
#     to --#{assistant_provider_groupings_filename}--, and modify columns to select patients to generate reports"
# end
#
# # =============================================================================
# # ====================  produce a file with statistics  =======================
#
# def proportion_stats( numerator, denominator)
#   if denominator > 0
#     mean = 1.0 * numerator / denominator
#     var = (mean * (1.0 - mean))
#     n = denominator
#     stderr = (var / n) ** 0.5
#     {
#       mean: mean,
#       var: var,
#       n_encounters: n,
#       stderr: stderr
#     }
#   else
#     {}
#   end
# end
#
#
# if !File.file?(stats_outpatient_filename) or !File.file?(stats_inpatient_filename) or (puts "\n\nRecalculate statistics for divisions?"; gets.chomp.downcase) == "y"
#
#
#     puts "Producing a report of the outpatient divisions --#{stats_outpatient_filename}--"
#     stats_outpatient_divisions = Hash[
#       @provider_groupings.select {|e| e["INCLUDE_IN_OUTPATIENT_STATS"] == "TRUE"}
#         .group_by {|e| e["OUTPATIENT_GROUP"] == "" ? "Uncategorized" : (e["OUTPATIENT_GROUP"] || "Uncategorized")}
#         .collect  do |group, providers|
#           prov_names_in_division = providers.collect {|e| e["PROV_NAME"]}
#           billings_for_division = @billing_data_all.select {|e| prov_names_in_division.include? e["PROV_NAME"]}
#           stats_for_division = BillingStats.outpatient_stats( billings_for_division )
#
#           # get the stats for each physician individually so can get a std deviation
#           puts "  Generating standard deviations using the providers in this division"
#           stats_for_individuals = billings_for_division.group_by {|e| e["PROV_NAME"]}.collect {|prov_name, billings_for_individual|
#             BillingStats.outpatient_stats( billings_for_individual ).collect {|k,v| [k, v[:mean]]}
#           }.flatten(1) # [:outpt_frac_initial_level_4_and_up, nil], [:outpt_frac_initial_level_5, nil], [:outpt_frac_followup_level_4_and_up, nil], [:outpt_frac_followup_level_5, nil], ...
#           stats_for_individuals.group_by {|k,v| k}.each {|k,values|
#             values = values.collect {|e| e[1]}.compact
#             stats_for_division[k][:stdev_by_provider] = values.any? ? values.standard_deviation : nil
#             stats_for_division[k][:n_providers] = values.size
#             if stats_for_division[k][:stdev_by_provider] != nil and stats_for_division[k][:mean] != nil
#               stats_for_division[k][:upper] = stats_for_division[k][:mean] + stats_for_division[k][:stdev_by_provider]
#               stats_for_division[k][:lower] = stats_for_division[k][:mean] - stats_for_division[k][:stdev_by_provider]
#             end
#           }
#
#         # outpatient
#         [group, { prov_names: prov_names_in_division }.merge(stats_for_division) ]
#       end
#     ]
#
#     File.open(stats_outpatient_filename,'w') do |h|
#        h.write stats_outpatient_divisions.to_yaml
#     end
#
#     puts "Producing a report of the inpatient divisions --#{stats_inpatient_filename}--"
#     stats_inpatient_divisions = Hash[
#       @provider_groupings.select {|e| e["INCLUDE_IN_INPATIENT_STATS"] == "TRUE"}
#         .group_by {|e| e["INPATIENT_GROUP"] == "" ? "Uncategorized" : (e["INPATIENT_GROUP"] || "Uncategorized")}
#         .collect  do |group, providers|
#         prov_names_in_division = providers.collect {|e| e["PROV_NAME"]}
#
#         billings_for_division = @billing_data_all.select {|e| prov_names_in_division.include? e["PROV_NAME"]}
#         stats_for_division = BillingStats.inpatient_stats( billings_for_division)
#
#         # get the stats for each physician individually so can get a std deviation
#           puts "  Generating standard deviations using the providers in this division"
#           stats_for_individuals = billings_for_division.group_by {|e| e["PROV_NAME"]}.collect {|prov_name, billings_for_individual|
#             BillingStats.inpatient_stats( billings_for_individual ).collect {|k,v| [k, v[:mean]]}
#           }.flatten(1) # [:outpt_frac_initial_level_4_and_up, nil], [:outpt_frac_initial_level_5, nil], [:outpt_frac_followup_level_4_and_up, nil], [:outpt_frac_followup_level_5, nil], ...
#           stats_for_individuals.group_by {|k,v| k}.each {|k,values|
#             values = values.collect {|e| e[1]}.compact
#             stats_for_division[k][:stdev_by_provider] = values.any? ? values.standard_deviation : nil
#             stats_for_division[k][:n_providers] = values.size
#             if stats_for_division[k][:stdev_by_provider] != nil and stats_for_division[k][:mean] != nil
#               stats_for_division[k][:upper] = stats_for_division[k][:mean] + stats_for_division[k][:stdev_by_provider]
#               stats_for_division[k][:lower] = stats_for_division[k][:mean] - stats_for_division[k][:stdev_by_provider]
#             end
#           }
#
#         [group, { prov_names: prov_names_in_division }.merge( stats_for_division ) ]
#       end
#     ]
#
#     File.open(stats_inpatient_filename,'w') do |h|
#        h.write stats_inpatient_divisions.to_yaml
#     end
# end
#
#
# # =============================================================================
# # =============================================================================
# def generate_and_save_individual_provider_report(provider, billing_entries, custom_filename=nil ) #
#   raise "no entries" if billing_entries.size == 0
#   puts "Producing report..."
#
#   # ==========================  generate a filename  ==========================
#   if custom_filename
#     provider_name_filesystem_friendly = custom_filename.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
#     filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
#   else
#     provider_name_filesystem_friendly = provider["PROV_NAME"].gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
#     filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
#   end
#
#   File.open( filename_complete , "w:UTF-8") do |file|
#     file.write(Reports.actionable(provider, billing_entries).gsub("\n", "\r\n"))
#   end
#   puts "  Saved as #{ filename_complete }"
# end
#
#
# providers_to_print = @provider_groupings.select {|e| e["GENERATE_REPORT"] == "TRUE"}
# puts "\n\nThis task will generate individual reports for --#{providers_to_print.size}-- providers. Continue?"
# if gets.chomp.downcase == "y"
#   providers_to_print.each do |provider|
#     generate_and_save_individual_provider_report(provider, @billing_data_all.select {|e|  e["PROV_NAME"] == provider["PROV_NAME"]}) #
#   end
# end
#
#
# # =============================================================================
# # =============================================================================
# providers_to_print = @assistant_provider_groupings.select {|e| e["GENERATE_REPORT"] == "TRUE"}
# puts "\n\nThis task will generate individual reports for --#{providers_to_print.size}-- ASSISTANT providers. Continue?"
# if gets.chomp.downcase == "y"
#   providers_to_print.each do |provider|
#     generate_and_save_individual_provider_report(
#       provider,
#       @billing_data_all.select {|e| e["SERV_PROV_NAME"] == provider["SERV_PROV_NAME"]},
#       provider["SERV_PROV_NAME"]
#     )
#   end
# end
#
#
# =============================================================================
# =============================================================================

puts Reports.sessions(selected_entries, clinic_sessions)

# def generate_and_save_sessions_report( encounters, filename = nil) #
#   raise "no entries" if encounters.size == 0
#   puts "Producing report..."
#   filename_complete = "report_sessions_#{ Time.now.strftime("%F") }.txt"
#
#   File.open(filename_complete , "w:UTF-8") do |file|
#     file.write(Reports.sessions(encounters))
#   end
#   puts "  Saved as #{ filename_complete }"
#
# end
#
#