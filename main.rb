# this script analyzes billing reports
# Report is calling “Charges, Payments and Adjustments”
# exported from business objects… (PROMIS)


require "csv"
require "./filters.rb"
require "./reports.rb"
# require 'yaml'

# =============================================================================
# ===============================  parameters  ================================
input_file = "neurologyvisitsjuly2014-november2017.csv"
timeslot_size = 15 # minutes
stats_odds_ratios_filename = "stats_odds_ratios.csv"
stats_odds_ratios_significant_filename = "stats_odds_ratios_significant.csv"
provider_grouping_template_filename = "provider_groupings_template.csv"
prediction_output_filename = "no_show_predictions.csv"


# =============================================================================
# ============================   load data file   =============================

puts "Loading data file #{ input_file }"
@encounters_all = CSV.read(input_file, {headers: true})
puts "  Loaded; there are #{ @encounters_all.size} rows"

puts "Loading zip code data"
distance_by_zip = Hash[CSV.read("zipcode_distances_from_19104.csv", {headers: true}).collect {|e| [e["ZIP"], e["DIST_KM"].to_f]}]
puts "  Loaded"

# =============================================================================
# ===========================   remove duplicates  ============================

# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
# 
@encounters_all = @encounters_all
  .select {|e| e["Appt Status"] == "Completed"}
  .uniq {|e| "#{ e["MRN"]}|#{e["Appt. Time"]}|#{ e["Appt. Length"] }|#{ e["Visit Type"] }"} +
  @encounters_all.select {|e| e["Appt Status"] != "Completed"}


# =============================================================================
# =========   fix timestamps and extract features for each encounter  =========

@encounters_all.each {|e| 
  e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
  e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
  e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
  e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
  begin
    e["appt_booked_on"] = DateTime.strptime(e["Appt. Booked on"], "%m/%d/%y") if e["Appt. Booked on"]
    e["appt_booked_on"] = nil if e["appt_booked_on"] > e["appt_at"] 
  rescue
    false
  end
    
  # e.g. timeslot   KIMBARIS, GRACE CHEN|2014-09-18|13:15
  e["timeslots"] = (0...(e["Appt. Length"].to_i)).step(timeslot_size).collect {|interval| 
    timeslot = e["appt_at"] + (interval / 24.0 / 60.0)
    "#{ e["Provider"]}|#{ timeslot.strftime("%F|%H:%M") }"  
  }
  
  zip = e["Zip Code"] ? e["Zip Code"][0..4].rjust(5, "0") : "absent"
  dist = distance_by_zip[ zip ]   # distance from hosp

  # we do a sparse encoding -- anything not listed in features is assumed to be 0
  e["features"] = {
   "zip_#{ zip }" => 1,
   "dist_#{ dist ? (2 ** Math.log(dist + 0.001, 2).round).to_f.round.to_s.rjust(4, "0") : "unknown"}_km" => 1,
   "age_decade_#{ (e["Age at Encounter"].to_i / 10.0).round }" => 1, 
   "gender_#{ e["Gender"].downcase }" => 1,
   "appt_hour_#{ e["appt_at"].hour.to_s.rjust(2, "0") }" => 1,
   "appt_made_#{ e["appt_booked_on"] ? (2 ** Math.log((e["appt_at"] - e["appt_booked_on"] + 1).to_f, 2).round).to_s.rjust(3, "0") : "unknown_" }d_advance" => 1,
   "appt_type_#{ e["Visit Type"].downcase }" => 1,
  }
  
  puts "Warning: #{ e["Appt. Length"] } min appt but #{ e["timeslots"].size } timeslots (#{e["timeslots"]})" if (1.0 * e["Appt. Length"].to_i / timeslot_size).to_i != e["timeslots"].size
}


# =============================================================================
# ===========================   features analysis   ===========================
# =====================  and calculation of odds ratios  ======================
features_for_show = @encounters_all.status_completed.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}
features_for_no_show = @encounters_all.status_no_show.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}

n_show = @encounters_all.status_completed.size
n_no_show = @encounters_all.status_no_show.size

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
    n_feature_and_show: n_feature_and_show,
    n_feature_and_no_show: n_feature_and_no_show,
    n_show: n_show,
    n_no_show: n_no_show,
    odds_ratio_of_no_show: odds_ratio,
    log_odds_ratio: log_odds_ratio,
    se_log_odds_ratio: se_log_odds_ratio,
    or_80_ci_lower: Math.exp(log_odds_ratio - 1.28 * se_log_odds_ratio ),
    or_80_ci_upper: Math.exp(log_odds_ratio + 1.28 * se_log_odds_ratio ),
    or_95_ci_lower: Math.exp(log_odds_ratio - 1.96 * se_log_odds_ratio ),
    or_95_ci_upper: Math.exp(log_odds_ratio + 1.96 * se_log_odds_ratio ),
    # significant: significant
  } 
}.sort_by {|e| e[:feature_name]}


headers = feature_statistics_array[0].keys

puts "Saving as --#{ stats_odds_ratios_filename }--"
CSV.open("#{ stats_odds_ratios_filename }", "wb") do |csv|
  csv << headers
  feature_statistics_array.each do |items| 
    csv << items.values
  end
end  

significant_feature_statistics_array = feature_statistics_array.select {|e| e[:or_80_ci_lower] > 1 or e[:or_80_ci_upper] < 1}

puts "Saving as --#{ stats_odds_ratios_significant_filename }--"
CSV.open("#{ stats_odds_ratios_significant_filename }", "wb") do |csv|
  csv << headers
  significant_feature_statistics_array.each do |items| 
    csv << items.values
  end
end  


log_odds_ratios_by_feature = Hash[significant_feature_statistics_array.collect {|e| [e[:feature_name], e[:log_odds_ratio]] }]


# =============================================================================
# ============  assign each encounter with a probability of no-show  ==========
@encounters_all.each {|e| 
  e[:log_odds_ratios_itemized] = e["features"].collect {|k,v|
    [k, log_odds_ratios_by_feature[k]]
  }
  
  sum_log_odds = e[:log_odds_ratios_itemized].collect {|f| f[1]}.compact.sum
  
  e[:odds_ratio_no_show] = Math.exp( sum_log_odds )
  
  pretest_odds = 0.1 / 0.9
  
  posttest_odds = e[:odds_ratio_no_show] * pretest_odds 
  
  e[:prob_no_show] = posttest_odds / (1 + posttest_odds)
}



# =============================================================================
# =======================  output a table of providers  =======================

puts "Generating provider list and saving as --#{ provider_grouping_template_filename }--"
CSV.open("#{ provider_grouping_template_filename }", "wb") do |csv|
  csv << ["PROV_NAME", "N_ENCOUNTERS", "GENERATE_REPORT"]
  @encounters_all.group_by {|e| e["Provider"]}.each do |prov_name, e| 
    csv << [prov_name, e.size, nil]
  end
end  
  

# "CSN":"95834500 " "Patient Name":"DOE,JOHN" "MRN":"012345589" "Age at Encounter":"60 " "Gender":"Male" "Ethnicity":"Non-Hispanic Non-Latino" "Race":"White" "Contact Date":" 01/16/2015" "Zip Code":"11111" "Appt. Booked on":"2014-10-17" "Appt. Time":" 01/16/2015  15:30 " "Checkin Time":" 01/16/2015  14:22 " "Appt Status":"Completed" "Referring Provider":"TORMENTI, MATTHEW J" "Department":"NEUROLOGY HUP" "Department ID":"378 " "Department Specialty":"Neurology" "Visit Type":"NEW PATIENT VISIT" "Procedure Category":"New Patient Visit" "Patient Class":"MAPS" "Provider":"RUBENSTEIN, MICHAEL NEIL" "Appt. Length":"60 " "Total Amount":"265.00"

# unfortunately, sometimes Appt. Booked on has format "2/26/14" %-m/%-d/%y

# Visit Type
# ["NEW PATIENT VISIT", "RETURN PATIENT VISIT", "EMG", "PROCEDURE", "BOTOX INJECTION", "LUMBAR PUNCTURE", "RESEARCH", "RETURN PATIENT TELEMEDICINE", "NEW PATIENT SICK", "ALLIED HEALTH NON CHARGEABLE", "EEG ROUTINE", "LABORATORY", "ESTABLISHED PATIENT SPECIALTY", "NEW PATIENT TELEMEDICINE", "INDEPENDENT MEDICAL EXAM"]

# Procedure Category
# ["New Patient Visit", "Return Patient Visit", "Office Procedure", "Research", nil]

# Appt Status
# ["Completed", "Canceled", "No Show", "Left without seen", "Arrived", "Scheduled"]

# Patient Class
# ["MAPS", "Outpatient", nil, "Family Accounts", "OFFICE VISITS", "AM Admit"]

# =============================================================================
# ========================   Pecularities of the data   =======================
# - sometimes there is identical patient in a slot twice, one cancelled, and one completed
# - Botox and EMG can sometimes have duplicate, triplicate, or even 4x of
#   same patient, same timeslot, same visit type, same status (completed)
#   DOE,JOHN EMG (Completed 15) / DOE,JOHN EMG (Completed 15)




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


# =============================================================================
# ==========================   generate reports   =============================

# puts Reports.sessions(selected_entries, clinic_sessions)

def generate_and_save_sessions_report( provider, encounters, custom_filename = nil) #
  raise "no entries" if encounters.size == 0
  puts "Producing report..."
  # ==========================  generate a filename  ==========================
  if custom_filename
    provider_name_filesystem_friendly = custom_filename.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
    filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
  else
    provider_name_filesystem_friendly = provider.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
    filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
  end

  clinic_sessions = extract_clinic_sessions( encounters )
  
  File.open(filename_complete , "w:UTF-8") do |file|
    file.write(Reports.sessions(encounters, clinic_sessions ).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete }"

end


selected_entries = @encounters_all.select {|e| e["Provider"] == "PRICE, RAYMOND"}
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)}
  # .sort_by {|e| e["appt_at"]}

generate_and_save_sessions_report( "PRICE, RAYMOND", selected_entries)
generate_and_save_sessions_report( "many providers", @encounters_all
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})

generate_and_save_sessions_report( "CHEN, MARIA FANG-CHUN", @encounters_all
.select {|e| e["Provider"] == "CHEN, MARIA FANG-CHUN"}
.select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})


# =============================================================================
# ==============================   output   ===================================


clinic_sessions = extract_clinic_sessions( selected_entries )

clinic_sessions.each do |clinic_session|
    puts "=== #{ clinic_session[:id] } / #{ clinic_session[:encounters].status_completed.sum_minutes } / #{ clinic_session[:hours_booked]} hb / #{ clinic_session[:visual] } / #{ (clinic_session[:visual].count(".") + clinic_session[:visual].count("X")) * 0.25}"

    clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.each do |time, entries_for_time|
      entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} #{ e["Visit Type"]} (#{ e["Appt Status"]} #{e["Appt. Length"]}) #{ e[:prob_no_show]}" }.join(" / ")
      puts "    #{ time }  #{ entries_text } "
    end

end

# =============================================================================
# ==============================   output   ===================================

headers = ["appt_at", "Provider", "Patient Name", "Visit Type", "Appt Status", :prob_no_show]

puts "Saving as --#{ prediction_output_filename }--"
CSV.open("#{ prediction_output_filename }", "wb") do |csv|
  csv << headers
  @encounters_all.each do |items| 
    csv << headers.collect {|header| items[header] }
  end
end  
