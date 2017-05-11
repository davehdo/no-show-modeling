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
input_file = "neurologyvisitsjuly2014-november2017.csv"
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
#
# @encounters_all = @encounters_all.to_a.uniq {|e|
#   if e["Appt Status"] == "Completed"
#     "#{ e["MRN"]}|#{e["timeslots[0]"]}|#{ e["Appt. Length"] }|#{ Visit Type }"
#   else
#     rand # send a rand so its uniq and gets kept
#   end
# }
# "CSN":"95834500 " "Patient Name":"DOE,JOHN" "MRN":"012345589" "Age at Encounter":"60 " "Gender":"Male" "Ethnicity":"Non-Hispanic Non-Latino" "Race":"White" "Contact Date":" 01/16/2015" "Zip Code":"11111" "Appt. Booked on":"2014-10-17" "Appt. Time":" 01/16/2015  15:30 " "Checkin Time":" 01/16/2015  14:22 " "Appt Status":"Completed" "Referring Provider":"TORMENTI, MATTHEW J" "Department":"NEUROLOGY HUP" "Department ID":"378 " "Department Specialty":"Neurology" "Visit Type":"NEW PATIENT VISIT" "Procedure Category":"New Patient Visit" "Patient Class":"MAPS" "Provider":"RUBENSTEIN, MICHAEL NEIL" "Appt. Length":"60 " "Total Amount":"265.00"

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
  clinic_sessions = encounters.group_by {|e| e["clinic_session"]}.collect {|session_id, encounters_in_session_raw|
    
    # amongst completed encounters, eliminate the duplicates associated with Botox and EMG
    # so we don't overcount minutes of patients seen
    # 
    encounters_in_session = encounters_in_session_raw
      .select {|e| e["Appt Status"] == "Completed"}
      .uniq {|e| "#{ e["MRN"]}|#{e["timeslots"][0]}|#{ e["Appt. Length"] }|#{ e["Visit Type"] }"} +
      encounters_in_session_raw.select {|e| e["Appt Status"] != "Completed"}

    
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



#
# =============================================================================
# =============================================================================

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


clinic_sessions = extract_clinic_sessions( selected_entries )

clinic_sessions.each do |clinic_session|
    puts "=== #{ clinic_session[:id] } / #{ clinic_session[:encounters].status_completed.sum_minutes } / #{ clinic_session[:hours_booked]} hb / #{ clinic_session[:visual] } / #{ (clinic_session[:visual].count(".") + clinic_session[:visual].count("X")) * 0.25}"

    clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.each do |time, entries_for_time|
      entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} #{ e["Visit Type"]} (#{ e["Appt Status"]} #{e["Appt. Length"]})" }.join(" / ")
      puts "    #{ time }  #{ entries_text }"
    end

end
