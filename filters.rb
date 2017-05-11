module Filters
  
    
  class ::Array
    # ========
    def sum
      self.inject(0){|accum, i| accum + i }
    end

    def mean
      self.sum/self.length.to_f
    end

    def sample_variance
      m = self.mean
      sum = self.inject(0){|accum, i| accum +(i-m)**2 }
      sum/(self.length - 1).to_f
    end

    def standard_deviation
      return Math.sqrt(self.sample_variance)
    end
    
    
    
    # Appt Status
    # ["Completed", "Canceled", "No Show", "Left without seen", "Arrived", "Scheduled"]
    
    
    # ======
    def status_completed
      self.select {|e| e["Appt Status"] == "Completed"}
    end

    def status_cancelled
      self.select {|e| e["Appt Status"] == "Canceled"}
    end
    
    def status_no_show
      self.select {|e| e["Appt Status"] == "No Show"}
    end

    def status_scheduled
      self.select {|e| e["Appt Status"] == "Scheduled"}
    end
    
    def future_sessions
      self.select {|e| e[:is_future_session]}
    end
 
    def past_sessions
      self.select {|e| !e[:is_future_session]}
    end   
    
    def providers
      self.collect {|e| e["Provider"]}
    end
    
    # "CSN":"95834500 " "Patient Name":"DOE,JOHN" "MRN":"012345589" "Age at Encounter":"60 " "Gender":"Male" "Ethnicity":"Non-Hispanic Non-Latino" "Race":"White" "Contact Date":" 01/16/2015" "Zip Code":"11111" "Appt. Booked on":"2014-10-17" "Appt. Time":" 01/16/2015  15:30 " "Checkin Time":" 01/16/2015  14:22 " "Appt Status":"Completed" "Referring Provider":"TORMENTI, MATTHEW J" "Department":"NEUROLOGY HUP" "Department ID":"378 " "Department Specialty":"Neurology" "Visit Type":"NEW PATIENT VISIT" "Procedure Category":"New Patient Visit" "Patient Class":"MAPS" "Provider":"RUBENSTEIN, MICHAEL NEIL" "Appt. Length":"60 " "Total Amount":"265.00"

    # Visit Type
    # ["NEW PATIENT VISIT", "RETURN PATIENT VISIT", "EMG", "PROCEDURE", "BOTOX INJECTION", "LUMBAR PUNCTURE", "RESEARCH", "RETURN PATIENT TELEMEDICINE", "NEW PATIENT SICK", "ALLIED HEALTH NON CHARGEABLE", "EEG ROUTINE", "LABORATORY", "ESTABLISHED PATIENT SPECIALTY", "NEW PATIENT TELEMEDICINE", "INDEPENDENT MEDICAL EXAM"]

    # Procedure Category
    # ["New Patient Visit", "Return Patient Visit", "Office Procedure", "Research", nil]

    # Appt Status
    # ["Completed", "Canceled", "No Show", "Left without seen", "Arrived", "Scheduled"]

    # Patient Class
    # ["MAPS", "Outpatient", nil, "Family Accounts", "OFFICE VISITS", "AM Admit"]
    

    #
    def sum_minutes
      self.collect {|e| e["Appt. Length"].to_i }.sum
    end
    #
    # def sum_quantity
    #   self.collect {|e| e["PROC_QTY"]}.inject(0){|sum,x| sum + x.to_f }.to_i
    # end
    #
    # def sum_charges
    #   self.collect {|e| e["CHARGES"]}.inject(0){|sum,x| sum + x.to_f }.to_i
    # end
    #
    # def sum_payments
    #   self.collect {|e| e["PAYMENTS"]}.inject(0){|sum,x| sum + x.to_f }.to_i
    # end
    #
    # def sum_credit_adj
    #   self.collect {|e| e["CREDIT_ADJ"]}.inject(0){|sum,x| sum + x.to_f }.to_i
    # end
    #
    # def sum_debit_adj
    #   self.collect {|e| e["DEBIT_ADJ"]}.inject(0){|sum,x| sum + x.to_f }.to_i
    # end
    #
    # def payments_per_unit # helps get a standard deviation estimate
    #   self.collect {|e|
    #     n = e["PROC_QTY"].to_i
    #     n > 0 ? (e["PAYMENTS"].to_f / n) : nil
    #   }.compact
    # end
  end
    

end