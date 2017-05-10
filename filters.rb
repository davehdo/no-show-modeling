module Filters
  
  def self.rvu_map 
    @rvu_hash ||= Hash[CSV.read("2017 0214 wRVU Value Pivot.csv", {headers: true}).collect {|e| [e["cpt_code"].to_s, e["Sum of wRVU Value"].to_f ]}]
    # {
#         "99201" =>  0,
#         "99202" =>  0.93,
#         "99203" =>  1.42,
#         "99204" =>  2.43,
#         "99205" =>  3.17,
#         "99241" =>  0,
#         "99242" =>  1.34,
#         "99243" =>  1.88,
#         "99244" =>  3.02,
#         "99245" =>  3.77,
#         "99211" =>  0.18,
#         "99212" =>  0.48,
#         "99213" =>  0.97,
#         "99214" =>  1.5,
#         "99215" =>  2.11,
#         "99221" =>  1.92,
#         "99222" =>  2.61,
#         "99223" =>  3.86,
#         "99251" =>  1,
#         "99252" =>  1.5,
#         "99253" =>  2.27,
#         "99254" =>  3.29,
#         "99255" =>  4,
#         "99283" =>  1.34,
#         "99284" =>  2.56,
#         "99285" =>  3.8,
#         "99218" =>  1.92,
#         "99219" =>  2.6,
#         "99220" =>  3.56,
#         "99231" =>  0.76,
#         "99232" =>  1.39,
#         "99233" =>  2,
#         "99238" =>  1.28,
#         "99239" =>  1.9,
#         "99217" =>  1.28,
#         "99224" =>  0.76,
#         "99225" =>  1.39,
#         "99226" =>  2,
#         "99291" =>  4.5,
#         "99292" =>  2.25,
#         "95867" =>  0.79,
#         "95885" =>  0.35,
#         "95886" =>  0.86,
#         "95887" =>  0.71,
#         "95907" =>  1,
#         "95908" =>  1.25,
#         "95909" =>  1.5,
#         "95910" =>  2,
#         "95911" =>  2.5,
#         "95912" =>  3,
#         "95913" =>  3.56,
#         "95937" =>  0.65,
#         "92585" =>  0.5,
#         "95926" =>  0.54,
#         "95930" =>  0.35,
#         "95938" =>  0.86,
#         "64405" =>  0.94,
#         "20552" =>  0.66,
#         "20553" =>  0.75,
#         "64612" =>  1.41,
#         "64616" =>  1.53,
#         "64642" =>  1.65,
#         "64644" =>  1.82,
#         "64646" =>  1.8,
#         "11100" =>  0.81,
#         "11101" =>  0.41,
#         "62270" =>  1.37,
#         "92585" =>  0.5,
#         "95829" =>  6.2,
#         "95860" =>  0.96,
#         "95861" =>  1.54,
#         "95864" =>  1.99,
#         "95867" =>  0.79,
#         "95868" =>  1.18,
#         "95885" =>  0.35,
#         "95886" =>  0.86,
#         "95887" =>  0.71,
#         "95907" =>  1,
#         "95908" =>  1.25,
#         "95909" =>  1.5,
#         "95910" =>  2,
#         "95911" =>  2.5,
#         "95912" =>  3,
#         "95913" =>  3.56,
#         "95925" =>  0.54,
#         "95926" =>  0.54,
#         "95927" =>  0.54,
#         "95930" =>  0.35,
#         "95938" =>  0.86,
#         "95940" =>  0.6,
#         "95955" =>  1.01,
#         "95961" =>  2.97,
#         "95962" =>  3.21,
#         "G0453" =>  0.6
#       }


      @rvu_hash
    end
    
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
    
    
    # def status_completed
    #   self.select {|e| e["Appt Status"] == "Completed"}
    # end
    #
    # def status_completed
    #   self.select {|e| e["Appt Status"] == "Completed"}
    # end
    

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