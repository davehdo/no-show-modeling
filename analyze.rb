module Analyze
   require "../filters.rb"
   require "csv"
   require 'yaml'
     
   # ==========================================================================
   # =========================  Weka-related helpers  =========================

   def self.save_collection( collection, filename )
     keys = collection.collect {|e| e.keys}.flatten.uniq
     
     CSV.open(filename, "w") do |csv|
       csv << keys
       collection.each do |row|
         csv << keys.collect {|k| row[k]}
       end
     end
   end
   
   
   def self.friendly_filename( input_string )
     input_string.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
   end
   
   def self.get_logistic_coefficients_from_classifier( classifier, training_instances )
      # because the intrinsic method for getting coefficients is not labeled
      # its non-trivial to match it up with the feature its describing
      #
      # we use a filter to simulate what the training method does, weeding out
      # non-information-carrying parameters e.g. omits male when female is defined
      
      require 'weka'
      import 'weka.filters.unsupervised.attribute.RemoveUseless'
      java_import 'weka.filters.Filter'

      coeffs = classifier.coefficients.collect {|e| e.collect {|f| f.to_f} }

      logit_filter = RemoveUseless.new 
      logit_filter.setInputFormat training_instances
      logit_filtered = Filter.useFilter(training_instances, logit_filter) # class instances

      # java_array = classifier.coefficients.to_a #converting java array to ruby
      # coeffs = java_array.map(&:to_a) #converting second level of java array to ruby
      # puts logit_filtered.inspect
      attr_val_pairs = logit_filtered.attributes.collect {|attr| 
      vals = attr.enumerateValues.collect {|f| f}
      (vals.size == 2 ? [vals.last] : vals).collect {|f| [attr.name, f]}
      }.flatten(1)

      raise "Error: there are #{ coeffs.size } coefficients and #{ attr_val_pairs.size } attr_val_pairs" unless coeffs.size == (attr_val_pairs.size + 1)

      table_unflattened = ([["Intercept", ""]] + attr_val_pairs).zip( coeffs.collect(&:first) )
      table = table_unflattened.collect {|e| e.flatten}
   end
  
  
   def self.add_instances_from_encounters_array( features_array, instances )
      feature_names = instances.attributes.collect {|e| e.name }
      # puts "Make sure these features are correct"
      # instances.attributes.each {|e| puts "  #{e.name} has options #{e.values}" }
      data = features_array.collect do |feature_hash|
       feature_names.collect {|feature_name| x=feature_hash[feature_name] }
      end
      instances.add_instances(data ) # , weight: 2.0
      instances
   end


  
   # ==========================================================================
   # =========================  CSV file manipulators  ========================
 
   def self.get_encounters_by_mrn( input_file_root= nil )
      # if @encounters_by_mrn
      #    @encounters_by_mrn
      # else
         raise "  please initialize encounters_by_mrn with data file" if input_file_root.nil?
         encounters_by_mrn = {}
         earliest_at = nil
         
         puts "  Assembling a list of prior encounters"
         CSV.foreach( "#{ input_file_root }.csv", headers: true) do |row|
            item = Hash[row]
            Analyze.parse_timestamps([item])
            if item["MRN"]
               encounters_by_mrn[ item["MRN"] ] ||= []
               encounters_by_mrn[ item["MRN"] ].push(
                  [item["appt_at"], item["Appt Status"]]
               )
            else
               "  *Warning: no MRN"
            end
            earliest_at = item["appt_at"] if earliest_at == nil or earliest_at > item["appt_at"]
         end
         [encounters_by_mrn, earliest_at]
         # @encounters_by_mrn = encounters_by_mrn
      # end
   end
   
   
   def self.extract_training_and_test_features_from_file(last_filename_root, training_fraction = 0.8, **args )
      args[:only_features_named] ||= nil

      # count the rows
      n_read = 0
      CSV.foreach( "#{last_filename_root}.csv", headers: true ) {|row| n_read += 1}
      valid_row_indexes = (0..n_read).to_a
      puts "  There are #{ valid_row_indexes.size} rows in #{ last_filename_root }"

      puts "Separating into training and test sets"
      test_indexes = valid_row_indexes.sample( (valid_row_indexes.size * (1.0 - training_fraction)).round)
      puts """  There should be #{valid_row_indexes.size - test_indexes.size} training and #{test_indexes.size} test instances"""

      puts "Extracting features for training and test sets"
      training_features = self.line_by_line_extract_features_from_file( last_filename_root, indexes: test_indexes, inverse: true, only_features_named: args[:only_features_named] )
      test_features = self.line_by_line_extract_features_from_file( last_filename_root, indexes: test_indexes, inverse: false, only_features_named: args[:only_features_named] )

      puts """  Done. Extracted features for #{ training_features.size } training and #{ test_features.size } test instances"""
      [training_features, test_features]
   end
   
   
   def self.line_by_line_extract_features_from_file( input_file_root, **args) # indexes=nil, inverse=false
      args[:indexes] ||= nil
      args[:inverse] ||= false # allow user to specify inverse, esp when the indexes array is longer than half the entries
      args[:only_features_named] ||= nil
      
     features = Array.new
     n_read = 0

     puts "  Now extracting features from each row sequentially in the file"
     CSV.foreach( "#{ input_file_root }.csv", headers: true ) do |row|
        if args[:indexes].nil? or 
           (args[:inverse] == false and args[:indexes].include?( n_read )) or 
           (args[:inverse] == true and !args[:indexes].include?( n_read ))
           item = Hash[row]
           
           # extractor was meant for multiple rows at once but this is a very 
           # large data set so we are doing line by line analysis
           # (loading into memory one at a time)

           Analyze.extract_features_from_array( [item], only_features_named: args[:only_features_named] )
           features << item["features"]
        end
        n_read += 1
        puts "  #{ n_read}" if n_read % 2000 == 0
     end
     features
   end


   def self.load_if( lambda_par, input_file_root, **args)
      entries = Array.new
      n_read = 0
      n_saved = 0
      puts "  Now loading relevant entries from file"
      CSV.foreach( "#{ input_file_root }.csv", headers: true ) do |row|
         item = Hash[row]
         
         Analyze.parse_timestamps( [item] )

         if lambda_par.call(item)
            entries << item
            n_saved += 1
         end

         n_read += 1
         puts "  #{ n_read}" if n_read % 10000 == 0
      end
      entries
   end
   
   
   def self.output_characteristics( root, **args )
     puts "Extracting and saving data set characteristics"
     args[:suffix] ||= "characteristics"
     args[:censor] ||= []
  
     puts "  Censor #{ args[:censor] }"
     check_overwrite( "#{root}_#{args[:suffix]}.yml" ) do
        
        output_hash = {:data_set => {}, :range => {}, :example_values => {}}
        
        n_rows = 0
        headers = []
        
        CSV.foreach( "#{ root }.csv", headers: true) do |row|
           if n_rows == 0
              headers = row.collect {|k,v| k}
           end
           
           row.each do |k,v|
              v = Analyze.censor(v) if args[:censor].include?(k)
              output_hash[:example_values][k] ||= []
              output_hash[:example_values][k].push( v) unless output_hash[:example_values][k].size > 20 or output_hash[:example_values][k].include?(v)
              
              output_hash[:range][k] ||= {}
              output_hash[:range][k][:min] ||= v.to_s
              output_hash[:range][k][:max] ||= v.to_s 
              output_hash[:range][k][:n_blank] ||= 0
              output_hash[:range][k][:class] ||= []
              
              output_hash[:range][k][:min] = v.to_s if v.to_s < output_hash[:range][k][:min] 
              output_hash[:range][k][:max] = v.to_s if v.to_s > output_hash[:range][k][:max]
              output_hash[:range][k][:n_blank] += 1 if v == nil
              output_hash[:range][k][:class].push(v.class.to_s) unless output_hash[:range][k][:class].include?(v.class.to_s)
              
           end
           
           n_rows += 1
        end
  
        output_hash[:data_set] = {
           filename: "#{root}_#{args[:suffix] }.yml",
           n_rows: n_rows,
           columns: headers
        }
        
        puts output_hash.inspect
        File.open("#{ root}_#{ args[:suffix] }.yml", 'w') {|f| f.write output_hash.to_yaml } #Store
     end
   end
  
  
  
   # ==========================================================================
   # ===========================  CSV file filters  ===========================

   def self.resave_sample( n_to_sample, root, suffix="samp" )
      puts "Taking a sample of the data"
      check_overwrite( "#{root}_#{suffix}.csv" ) do  
         n_rows = 0
         CSV.foreach( "#{ root }.csv", headers: true) { n_rows += 1}
         keep = (0...n_rows).to_a.sample(n_to_sample)

         resave_if( lambda {|item, i, s| keep.include?(i)}, root, suffix) 
      end
      "#{ root }_#{ suffix }"
   end
  
  
   # def self.resave_followups_only( root, suffix="fu" )
   #   resave_if( lambda {|item, i, s| [item].type_office_followup.any?}, root, suffix)
   # end
   #


   def self.resave_without_dup( root, suffix="fu", uniqueness= nil )
      uniqueness ||= lambda {|e| "#{ e["Appt Status"]}|#{ e["MRN"]}|#{e["Appt. Time"]}|#{ e["Appt. Length"] }|#{ e["Visit Type"] }"}
  
      output_file = "#{ root }_#{ suffix }.csv"
      check_overwrite( output_file ) do
      
         contents = File.read( "#{ root }.csv" )
         csv_obj = CSV.new( contents, headers: true)
  
         # raise csv_obj.inspect
         rows_and_unique_key = Array.new

         csv_obj.each_with_index do |csv_row, i|
            rows_and_unique_key << [i, uniqueness.call( csv_row ) ]
         end

         keepers = rows_and_unique_key.uniq {|a, b| b}.collect {|a,b| a}
         puts "  Duplicate-removal would reduce from #{ rows_and_unique_key.size } to #{ keepers.size } rows"

         resave_if( lambda {|item, i, s| keepers.include?(i)}, root, suffix)
      end
      "#{ root }_#{ suffix }"
   end


   def self.resave_if(lamda_block, root, suffix="fu" )
      input_file = "#{ root }.csv"
      output_file = "#{ root }_#{ suffix }.csv"

      if !File.exists?( output_file ) or confirm("  Warning: Overwrite #{ output_file }?")
         puts "Loading data file #{ input_file }"

         n_read = 0
         n_saved = 0

         CSV.open("#{ output_file }", "wb") do |csv_out|

            CSV.foreach( input_file, headers: true ) do |row|
               if n_read == 0
                  headers = row.collect {|a,b| a}
                  csv_out << headers
               end

               item = Hash[row]
               Analyze.parse_timestamps( [item] )
               # raise item.inspect
               if lamda_block.call(item, n_read, n_saved)
                  csv_out << row.collect {|a,b| b} 
                  n_saved += 1
                  puts "  Saved #{n_saved}" if n_saved % 5000 == 0
               end
               n_read += 1
            end
         end

         puts "  Saved #{ n_saved } records (of #{n_read}) into #{ output_file}"
      end
      "#{ root }_#{ suffix }"
   end
 

   def self.resave_without_columns(root, suffix="mask", **args )
      require 'digest'
      
      args[:omit] ||= []
      args[:mask] ||= []
      
      col = Hash[args[:omit].collect {|e| [e.to_s, :omit]} + args[:mask].collect {|e| [e.to_s, :mask]}]
      
      input_file = "#{ root }.csv"
      output_file = "#{ root }_#{ suffix }.csv"

      if !File.exists?( output_file ) or confirm("  Warning: Overwrite #{ output_file }?")
         puts "Loading data file #{ input_file }"

         n_saved = 0

         CSV.open("#{ output_file }", "wb") do |csv_out|

            CSV.foreach( input_file, headers: true ) do |row|
               if n_saved == 0
                  headers = row.collect {|a,b| a}
                  csv_out << headers.collect {|h|
                     case col[h]
                     when :omit
                        "#{h} (OMIT)"
                     when :mask
                        "#{h} (MASK)"
                     else
                        h
                     end
                  }
               end
               
               csv_out << row.collect {|a,b| 
                  case col[a]
                  when :omit
                     nil
                  when :mask
                     b ? Digest::MD5.hexdigest(b) : b
                  else
                     b
                  end
               }
               
               n_saved += 1
            end
         end

         puts "  Saved #{ n_saved } records into #{ output_file}"
      end
      "#{ root }_#{ suffix }"
   end
 
 
   def self.get_list_of_residents( root, **args )
      # residents typically are the providers whos patients are monday/thurs PM
      provider = {}
      
      CSV.foreach( "#{ root }.csv", headers: true ) do |row|
         item = Hash[row]
         Analyze.parse_timestamps( [item] )
         time_slot_of_interest = ["Thu PM", "Mon PM"].include?(item["appt_at"].strftime("%a %p") )
         provider[item["Provider"]] ||= [0, 0]
         provider[item["Provider"]][time_slot_of_interest ? 0 : 1] += 1
      end
      
      puts provider.inspect
      provider
   end
   
   
   def self.resave_with_prior_visit_counts( root, **args )
      puts "Resaving each with a "
      args[:suffix] ||= "counts"
     
      input_file = "#{ root }"
      output_file = "#{ root }_#{ args[:suffix] }"

      check_overwrite( "#{output_file}.csv" ) do
        n_read = 0
        features = Array.new
        encounters_by_mrn, earliest_at = get_encounters_by_mrn( root )
        
        CSV.open("#{ output_file }.csv", "wb") do |csv_out|

           CSV.foreach( "#{ input_file }.csv", headers: true ) do |row|
              if n_read == 0
                 headers = row.collect {|a,b| a}
                 csv_out << headers + ["prior_show_past_2yr", "prior_noshow_past_2yr", "prior_cancel_past_2yr"]
              end

              item = Hash[row]
              Analyze.parse_timestamps( [item] )
              
              # =======================  prior counts  ========================
              if earliest_at + 730 > item["appt_at"]
                 counts = [nil, nil, nil]
              else
                 # extract additional features
                 enc = (encounters_by_mrn[ item["MRN"] ] || [])
                    .select {|date, status| date > (item["appt_at"] - 730) and date < item["appt_at"] }
      
                 counts = [                    
                    (x=enc.count {|date, status| status == "Completed"}) > 5 ? ">5" : x,
                    (x=enc.count {|date, status| status == "No Show"}) > 5 ? ">5" : x,
                    (x=enc.count {|date, status| status == "Canceled"}) > 5 ? ">5" : x
                 ]
              end
              
              # =========================  attg/res  ==========================
              
              
              csv_out << row.collect {|a,b| b} + counts
              
              puts "  #{ n_read}" if n_read % 2000 == 0
     
              n_read += 1
           end
        end
     end
     output_file
   end
  

  
   # ==========================================================================
   # ==========================================================================
  
  def self.distance_by_zip
      puts "  Loading zip code data" unless @distance_by_zip
      @distance_by_zip ||= Hash[CSV.read("../zipcode_distances_from_19104.csv", {headers: true}).collect {|e| [e["ZIP"], e["DIST_KM"].to_f]}]
  end


  def self.diagnosis_icd10_mappings
    if @diagnosis_icd10_mappings
      @diagnosis_icd10_mappings
    else
      raise "diagnosis_icd10_mappings is generated when running diagnoses_by_mrn"
    end
  end
    
  def self.n_diagnosis_codes_in_first_encounter_by_mrn( input_root = "../sources/neurology_provider_visits_with_payer_20170608")
    if @n_diagnosis_codes_in_first_encounter_by_mrn
      @n_diagnosis_codes_in_first_encounter_by_mrn
    else
      
      raise "finish implementing this"
      diagnoses_by_mrn = {}
      diagnoses_and_icds = []

      puts "Creating a master hash of n_diagnosis_codes_in_first_encounter_by_mrn"
      n_read = 0
      CSV.foreach( "#{ input_root }.csv", headers: true ) do |row|
        if n_read == 0
           headers = row.collect {|a,b| a}
        end

        item = Hash[row]

        diagnoses_by_mrn[item["MRN"]] ||= []
      
        diagnoses = [item["DX1 ICD10"], item["DX2 ICD10"], item["DX3 ICD10"], item["DX4 ICD10"], item["DX5 ICD10"]]
          .select {|e| e != nil and e.strip != ""}

        # group if appropriate
        diagnoses = diagnoses.collect {|icd| 
          match = icd_by_group.find {|nm, icd_list| icd_list.include?(icd)} # should  return [nm, icd]
          match ? match[1].join("|") : icd
        }
          
        diagnoses_and_icds = diagnoses_and_icds + [
          [item["DX1 Name"], item["DX1 ICD10"]],
          [item["DX2 Name"], item["DX2 ICD10"]],
          [item["DX3 Name"], item["DX3 ICD10"]],
          [item["DX4 Name"], item["DX4 ICD10"]],
          [item["DX5 Name"], item["DX5 ICD10"]]
        ].select {|dx, icd| dx != nil and dx.strip != ""}
        
        
        diagnoses_by_mrn[item["MRN"]] = (diagnoses_by_mrn[item["MRN"]] + diagnoses).uniq
        n_read += 1
      end
      puts "  done"


      # ===================. consolidate the mapping table. ===================
      @diagnosis_icd10_mappings = icd_by_group.collect {|name, icd_list|
          {
            name: name, 
            name_norm: "dx_#{ self.friendly_filename( name ) }", 
            icd: v = icd_list.join("|"), 
            icd_norm: "dx_#{ self.friendly_filename( v ) }", 
          }
      } + diagnoses_and_icds.group_by {|dx_name,icd| "#{dx_name}|#{icd}"}
        .collect {|name_and_icd,entries|
          k,v = entries[0]
          { 
            icd: v, 
            icd_norm: "dx_#{ self.friendly_filename( v ) }", 
            name: k, 
            name_norm: "dx_#{ self.friendly_filename( k ) }", 
            n_occurances: entries.size
          }
      }.sort_by {|r| "#{r[:icd]}|#{ (10000000 - (r[:n_occurances] || 0)).to_s.rjust(8, "0")}"}

      diagnosis_icd10_mappings_filename = "./diagnosis_icd10_mappings.csv"
      puts "  Writing a table of ICD10 and diagnosis names for reference: #{ diagnosis_icd10_mappings_filename }"
      
      self.save_collection( @diagnosis_icd10_mappings,  diagnosis_icd10_mappings_filename)


            # =========================  attg/res  ==========================
      @diagnoses_by_mrn = diagnoses_by_mrn   
    end  
  end

    
  def self.diagnoses_by_mrn( input_root = "../sources/neurology_provider_visits_with_payer_20170608")
    if @diagnoses_by_mrn
      @diagnoses_by_mrn
    else
      
      # ==========================  diagnosis group  ==========================
      # generated from looking at all diagnoses in neurology clinic with prevalance more than 0.5%
      # anything not in this list of groups should be interpreted as its own entity
      icd_by_group = {
        "Brain neoplasm" => ["D49.6", "C71.9"],
        "Dementia" => ["F03.90", "F03.91"],   
        "Alzheimer disease" => ["G30.0", "G30.1", "G30.8", "G30.9"],   
        "Localization-related epilepsy" => ["G40.009",
          "G40.019",
          "G40.109",
          "G40.119",
          "G40.209",
          "G40.219"],
        "Generalized epilepsy" => ["G40.309",
          "G40.319",
          "G40.409"],        
        "Lennox-Gastaut syndrome" => ["G40.812", "G40.814"],
        "Seizures or seizure disorder" => ["G40.909","G40.919", "G40.802", "R56.9"],        
        "Juvenile myoclonic epilepsy" => ["G40.B09", "G40.B19"],
        "Migraine" => ["G43.009", "G43.109", "G43.711", "G43.719", "G43.909"],        
        "Double vision or other vision complaint" => ["H53.2", "H53.40", "H53.8", "H53.9", "H54.7" ],
        "Radiculopathy, back pain, or neck pain" => ["M54.12", "M54.16", "M54.17", "M54.2", "M54.5", "M54.81", "M54.9"],        
        "Gait instability, disorder, imbalance, or ataxia" => ["R26.81", "R26.89", "R26.9", "R27.0"],
        "Abnormal MRI" => ["R90.89", "R93.0", "R93.8"],        
        "Osteomalacia or osteoporosis" => ["M83.5", "T42.71XS", "T42.75XA", "T50.901A", "M81.0", "M85.80"],
        "Encounter for drug monitoring or long-term use of medications" => ["Z51.81", "Z79.899"],
        "Numbness or sensory disturbance" => ["R20.9", "R20.2", "R20.0"],
        "Neuropathy" => ["G60.3", "G60.8", "G60.9", "G61.81", "G62.9"],
        "Pain" => ["R52", "M79.2", "M79.609"],
        "Weakness or muscle weakness" => ["R53.1", "M62.81"],
        "Memory loss, cognitive impairment or mild cognitive impairment or cognitive and behavior changes" => ["G31.84", "R41.89", "R41.3", "R46.89"],
        "Carpal tunnel syndrome" => ["G56.01", "G56.03"], 
        "Foot drop" => ["M21.372", "M21.371", "M21.379"],
        "Stroke, TIA, or cerebrovascular disease" => ["I63.9", "I67.9", "G45.9"],
        "Tremor or essential tremor" => ["R25.1", "G25.0"],
        "Multiple sclerosis or demyelinating changes" => ["G35", "G37.9"],
        "Hyperreflexia or spasticity" => ["R29.2", "R25.2"],
      }
      
      
      
      diagnoses_by_mrn = {}
      diagnoses_and_icds = []

      puts "Creating a master hash of diagnoses by MRN"
      n_read = 0
      CSV.foreach( "#{ input_root }.csv", headers: true ) do |row|
        if n_read == 0
           headers = row.collect {|a,b| a}
        end

        item = Hash[row]

        diagnoses_by_mrn[item["MRN"]] ||= []
      
        diagnoses = [item["DX1 ICD10"], item["DX2 ICD10"], item["DX3 ICD10"], item["DX4 ICD10"], item["DX5 ICD10"]]
          .select {|e| e != nil and e.strip != ""}

        # group if appropriate
        diagnoses = diagnoses.collect {|icd| 
          match = icd_by_group.find {|nm, icd_list| icd_list.include?(icd)} # should  return [nm, icd]
          match ? match[1].join("|") : icd
        }
          
        diagnoses_and_icds = diagnoses_and_icds + [
          [item["DX1 Name"], item["DX1 ICD10"]],
          [item["DX2 Name"], item["DX2 ICD10"]],
          [item["DX3 Name"], item["DX3 ICD10"]],
          [item["DX4 Name"], item["DX4 ICD10"]],
          [item["DX5 Name"], item["DX5 ICD10"]]
        ].select {|dx, icd| dx != nil and dx.strip != ""}
        
        
        diagnoses_by_mrn[item["MRN"]] = (diagnoses_by_mrn[item["MRN"]] + diagnoses).uniq
        n_read += 1
      end
      puts "  done"


      # ===================. consolidate the mapping table. ===================
      @diagnosis_icd10_mappings = icd_by_group.collect {|name, icd_list|
          {
            name: name, 
            name_norm: "dx_#{ self.friendly_filename( name ) }", 
            icd: v = icd_list.join("|"), 
            icd_norm: "dx_#{ self.friendly_filename( v ) }", 
          }
      } + diagnoses_and_icds.group_by {|dx_name,icd| "#{dx_name}|#{icd}"}
        .collect {|name_and_icd,entries|
          k,v = entries[0]
          { 
            icd: v, 
            icd_norm: "dx_#{ self.friendly_filename( v ) }", 
            name: k, 
            name_norm: "dx_#{ self.friendly_filename( k ) }", 
            n_occurances: entries.size
          }
      }.sort_by {|r| "#{r[:icd]}|#{ (10000000 - (r[:n_occurances] || 0)).to_s.rjust(8, "0")}"}

      diagnosis_icd10_mappings_filename = "./diagnosis_icd10_mappings.csv"
      puts "  Writing a table of ICD10 and diagnosis names for reference: #{ diagnosis_icd10_mappings_filename }"
      
      self.save_collection( @diagnosis_icd10_mappings,  diagnosis_icd10_mappings_filename)


            # =========================  attg/res  ==========================
      @diagnoses_by_mrn = diagnoses_by_mrn   
    end  
  end

   # ==========================================================================
   # =========================  Encounter manipulators  =======================
  
  def self.extract_features_from_array( encounters_all, **args )
    puts "Extracting features" unless encounters_all.size < 2

    args[:only_features_named] ||= nil
    
    raise "Please specify only_features_named as array which may include 'diagnosis_features' and or 'pt_appt_features" if args[:only_features_named] == nil or args[:only_features_named] == []
    
    # in order to find specific patient's prior encounters
    # encounters_by_mrn = encounters_all.group_by {|e| e["MRN"]}

    encounters_all.each {|e| 
      # we use either diagnosis_features or regular features because too many features can make the model run extremely slowly
      if args[:only_features_named].include?( "diagnosis_features" )
          diagnoses = (diagnoses_by_mrn[e["MRN"]] || []).collect {|e| ["#{ e.strip }", 1]}
          
          e["features"] = {
            "outcome" => [e].status_no_show.any? ? "no_show" : ([e].status_completed.any? ? "show" : nil),
          }
          if diagnoses.any?
            e["features"] = e["features"].merge(Hash[ diagnoses ]) 
          else
            e["features"]["no_diagnoses_listed"] = 1;
          end
      end    
      
      if args[:only_features_named].include?( "pt_appt_features" )

          e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
          # e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
          e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
          # e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
          # e.g. # 2015-01-19
          e["appt_booked_on"] = DateTime.strptime(e["Appt. Booked on"], "%F") if e["Appt. Booked on"]
        
          zip = e["Zip Code"] ? e["Zip Code"].to_s.strip[0..4].rjust(5, "0") : nil
          dist = distance_by_zip[ zip ]   # distance from hosp

          if ["", nil].include?(e["Benefit Plan"])
             benefit_plan_category = "BLANK"
          elsif e["Benefit Plan"] =~ /medicare/i
             benefit_plan_category = "medicare"
          elsif e["Benefit Plan"] =~ /medicaid/i
             benefit_plan_category = "medicaid"
          else
             benefit_plan_category = "other"
          end
      
          # raise "Data set is missing constructed column prior_show_past_2yr. Did you run script to add columns for counts?" unless e["prior_show_past_2yr"]
          e["features"] = {
            "dist_km" => Analyze.categorize_continuous_var_by_boundaries(dist, (1..10).collect {|n| 2 ** n} ) || "UNKNOWN",
            "age_decade" => Analyze.categorize_continuous_var_by_boundaries( e["Age at Encounter"].to_i, (10..90).step(10)) || "UNKNOWN",
            # "zip_code" => zip || "ABSENT",
            # "zip_3" => zip ? zip.slice(0,3) : "ABSENT",
            "gender" => e["Gender"].downcase == "male" ? "male" : "female",
            "appt_made_d_advance" =>  Analyze.categorize_continuous_var_by_boundaries(e["appt_booked_on"] ? (e["appt_at"] - e["appt_booked_on"] ) : nil, (1..8).collect {|n| 2 ** n} ) || "UNKNOWN",
            "dept" => e["Department"].downcase.gsub(" ", "_"),
            "appt_hour" => e["appt_at"].hour.to_s.rjust(2, "0"),
            "appt_type" => e["Visit Type"].downcase,
            # "last_contact" =>  Analyze.categorize_continuous_var_by_boundaries(e["contacted_on"] ? (e["appt_at"] - e["contacted_on"]) : nil, (1..8).collect {|n| 2 ** n} ) || "UNKNOWN",
            "outcome" => [e].status_no_show.any? ? "no_show" : ([e].status_completed.any? ? "show" : nil),
            "payer" => benefit_plan_category, 
            "prior_show_past_2yr" => e["prior_show_past_2yr"],
            "prior_noshow_past_2yr" => e["prior_noshow_past_2yr"],
            "prior_cancel_past_2yr" => e["prior_cancel_past_2yr"],
            "session" => e["appt_at"].strftime("%a %p"),
            # "n_diagnoses" => [e["DX1 ICD10"], e["DX2 ICD10"], e["DX3 ICD10"], e["DX4 ICD10"], e["DX5 ICD10"]].count {|e| e != nil and e.strip != ""},
            # "n_medications" => [e["Order 1 Med ID"], e["Order 2 Med ID"], e["Order 3 Med ID"], e["Order 4 Med ID"], e["Order 5 Med ID"]].count {|e| e != nil and e.strip != ""},
            "race" => e["Race"],
            # "provider" => e["Provider"]
          }.select {|k,v| v!=nil and ( args[:only_features_named].nil? or args[:only_features_named].include?(k)) }
      end
    }
    # puts "  done"
    encounters_all
  end
  
  
    
  
  def self.parse_timestamps( encounters_all, timeslot_size = 15 )
    puts "Parsing timestamps" unless encounters_all.size < 2
    encounters_all.each {|e| 
      e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
      # e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
      e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
      # e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
      # e.g. # 2015-01-19
      e["appt_booked_on"] = DateTime.strptime(e["Appt. Booked on"], "%F") if e["Appt. Booked on"]
      #   e["appt_booked_on"] = nil if e["appt_booked_on"] > e["appt_at"]
      # rescue
      #   false
      # end
    
      # e.g. timeslot   KIMBARIS, GRACE CHEN|2014-09-18|13:15
      e["timeslots"] = (0...(e["Appt. Length"].to_i)).step(timeslot_size).collect {|interval|
        timeslot = e["appt_at"] + (interval / 24.0 / 60.0)
        "#{ e["Provider"]}|#{ timeslot.strftime("%F|%H:%M") }"
      }
      # puts "  Warning: prov has #{ e["Appt. Length"] } min appt but our analysis uses #{ timeslot_size } min timeslots (#{e["timeslots"]})" if (1.0 * e["Appt. Length"].to_i / timeslot_size).to_i != e["timeslots"].size
  
    }
    puts "  done" unless encounters_all.size < 2
    encounters_all
  end



   # ==========================================================================
   # ===============================  Utilities  ==============================

   def self.confirm(prompt = 'Continue?' )
     puts prompt

     until ["y", "n"].include?(response = gets.chomp.downcase)
       puts "#{ prompt } (y/n)"
    
     end
     response == 'y'
   end

   def self.check_overwrite( output_file )
      if !File.exists?( output_file ) or confirm("  Warning: Overwrite #{ output_file }?")
         yield
      end
   end


  # in string, replaces all the digits with 9 and letters with x or X
  def self.censor( par )
     if par.class == String
        par.gsub(/\d/, "9").gsub(/[a-z]/, "x").gsub(/[A-Z]/, "X")
     else
        puts "Warning: do not know how to censor a #{ par.class }"
     end
  end
  
    #
  # boundaries = (0..5).collect {|e| 2 ** e }
  #
  # puts "boundaries #{ boundaries }"
  #
  # [-5, 0.2, 0, 1, 3, 5, 8, 100, 1000, 100000].each do |n|
  #    puts "#{n} cat as #{ Analyze.categorize_continuous_variable_by_boundaries(n, boundaries) }"
  # end
  #
  #
  def self.categorize_continuous_var_by_boundaries( var=nil, boundaries_array )
     sorted = (boundaries_array.class == Enumerator ? boundaries_array.to_a : boundaries_array).clone.sort_by {|e| e}
     if var == nil
        nil
     elsif var < sorted.first
        "<#{boundaries_array.min}"
     elsif var >= sorted.last
        ">=#{boundaries_array.max}"
     else
        prior = sorted.shift
        while !(prior...(current = sorted.shift)).include?( var )
           prior = current
        end
        "#{ prior}...#{current}" 
     end
  end
  
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
     raise "see train_odds_ratios"
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


  def self.filter_by_prevalence( features_array, min_prevalence = 0.005 )
    minimum_n ||= (min_prevalence * features_array.size).floor
    
    
    features_names_with_enough = features_array.collect {|e| e.to_a}
      .flatten(1).group_by {|k,v| k}.collect do |feature_name, all_values|
         # puts "#{ feature_name } : #{ all_values.size }"
         if all_values.size >= minimum_n
            feature_name
         else
            puts "  filter_by_prevalence: Feature\t#{ feature_name }\tomitted because does not meet minumum n of #{ minimum_n }\t#{ all_values.size }"
            nil
         end
    end.compact 
    
    features_array.collect {|e| e.select {|k,v| features_names_with_enough.include?(k)}}
  end
  
  
  # see specs/analyze_spec.rb 
  # univariate
   def self.train_odds_ratios( features_array, **args )
      # expect the outcome key
      args[:outcome] ||= "outcome"
      
      # only analyze features with a certain prevalance
      args[:min_prevalence] ||= 0.005
      args[:min_posttest_prob] ||= 0.0
      
      args[:filter_significant ] ||= false
      
      minimum_n ||= (args[:min_prevalence] * features_array.size).floor
      
      puts "Train odds ratios"
      puts "  Getting prototype features and values"
      
      # assemble a hash {"feature_name" => ["value 1", "value 2", "value 3"]}
      features_hash = Hash[features_array.collect {|e| e.to_a}
        .flatten(1).group_by {|k,v| k}.collect do |feature_name, all_values|
           # puts "#{ feature_name } : #{ all_values.size }"
           if all_values.size >= minimum_n or feature_name == args[:outcome]
              unique_values =  all_values.collect {|k,v| v}.uniq
              [feature_name, unique_values]
           else
              puts "  Odds ratio calculator: Feature\t#{ feature_name }\tomitted because does not meet minumum n of #{ minimum_n }\t#{ all_values.size }"
              nil
           end
      end.compact ]

      raise "  Err: There are no features meeting minimum threshold" if features_hash.size == 0
      
      # raise "There needs to be two types of values for #{ args[:outcome] }" unless features_hash[args[:outcome]].size == 2
      possible_outcome_values = features_hash[args[:outcome]]
      
      puts "  Calculating for #{ possible_outcome_values.size} possible outcome values and the following features: #{ features_hash.keys }"
      
      # go through each outcome
      possible_outcome_values.map do |outcome_0|
         puts "    Calculating for #{args[:outcome]}=#{ outcome_0 }"

         entries_with_given_outcome = features_array.select {|e| e[args[:outcome]] == outcome_0 }
         entries_without_given_outcome = features_array - entries_with_given_outcome
         
         n_outcome_0 = entries_with_given_outcome.size
         n_outcome_1 = entries_without_given_outcome.size
         
         # go through each feature key
         features_hash.select {|feat_name, v| feat_name != args[:outcome]}.collect {|feature_name, possible_values|
            
            entries_with_given_outcome_by_feature_value = entries_with_given_outcome.collect {|e| e[feature_name] }.group_by {|e| e }
            entries_without_given_outcome_by_feature_value = entries_without_given_outcome.collect {|e| e[feature_name] }.group_by {|e| e }
            
            
            # go through each possible feature value
            possible_values.collect {|val| 

               n_feature_and_outcome_0 = (entries_with_given_outcome_by_feature_value[ val ] || []).size
               n_feature_and_outcome_1 = (entries_without_given_outcome_by_feature_value[ val ] || []).size

               # per md-calc https://www.medcalc.org/calc/odds_ratio.php

               a = n_feature_and_outcome_0 # exposed, bad outcome
               c = n_outcome_0 - n_feature_and_outcome_0 # control, bad outcome
               b = n_feature_and_outcome_1 # exposed, good outcome
               d = n_outcome_1 - n_feature_and_outcome_1 # control, good outcome

               odds_ratio = 1.0 * a * d / ( b * c)
               log_odds_ratio = Math.log( odds_ratio ) # base e
               se_log_odds_ratio = Math.sqrt( (1.0 / a) + (1.0 / b) + (1.0 / c) + (1.0 / d))
               # significant = (Math.exp(log_odds_ratio - 1.96 * se_log_odds_ratio )  > 1.0) or ( Math.exp(log_odds_ratio + 1.96 * se_log_odds_ratio < 1.0))
               odds_outcome_0_given_feature  = n_outcome_0 / n_outcome_1 * odds_ratio
               or_95_ci_lower = Math.exp(log_odds_ratio - 1.96 * se_log_odds_ratio )
               or_95_ci_upper = Math.exp(log_odds_ratio + 1.96 * se_log_odds_ratio )
               
               
               {
                   feature_name_value: "#{feature_name}=#{val}",
                   feature_name: feature_name,
                   feature_value: val,
                  odds_ratio_outcome_0: odds_ratio,
                  odds_ratio_text: "#{ odds_ratio.round(2) } (#{or_95_ci_lower.round(2)}-#{or_95_ci_upper.round(2)})",
                  outcome_0: outcome_0,
                  or_95_ci_lower: or_95_ci_lower,
                  or_95_ci_upper: or_95_ci_upper,
                  n_feature_and_outcome_0: n_feature_and_outcome_0,
                  n_feature_and_outcome_1: n_feature_and_outcome_1,
                  n_outcome_0: n_outcome_0,
                  n_outcome_1: n_outcome_1,
                  log_odds_ratio: log_odds_ratio,
                  se_log_odds_ratio: se_log_odds_ratio,
                  prob_outcome_0_given_feature: odds_outcome_0_given_feature / (1 + odds_outcome_0_given_feature),
                 # or_80_ci_lower: Math.exp(log_odds_ratio - 1.28 * se_log_odds_ratio ),
                 # or_80_ci_upper: Math.exp(log_odds_ratio + 1.28 * se_log_odds_ratio ),
                 # significant: significant,
               }
            } # /each feature value

       }.flatten.select {|e| !args[:filter_significant ] or e[:or_95_ci_lower] > 1 or e[:or_95_ci_upper] < 1}
           .select {|e| e[:prob_outcome_0_given_feature] >= args[:min_posttest_prob] }
    end.flatten
  end
  
    
  def self.extract_clinic_sessions( encounters )
    clinic_sessions = encounters.group_by {|e| e["clinic_session"]}.sort_by {|k,v|k}.collect {|session_id, encounters_in_session|
  
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

      hours_booked = ((encounters_in_session.status_completed + encounters_in_session.status_no_show + encounters_in_session.status_scheduled).sum_minutes || 0) / 60.0
  
      {
        id: session_id, 
        timeslots: timeslots,
        provider: parts[0],
        date: Date.parse( parts[1] ),
        am_pm: parts[2],
        encounters: encounters_in_session.sort_by {|f| f["appt_at"]},
        hours_booked: hours_booked,
        hours_completed: ((encounters_in_session.status_completed ).sum_minutes || 0) / 60.0,
        is_partial_session: hours_booked < 1.5,
        is_future_session: ((encounters_in_session.status_scheduled ).sum_minutes || 0) >= 30,
        visual: visual,
      }
    }
  end

end