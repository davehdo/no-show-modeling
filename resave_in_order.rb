require "csv"

root = "odds_ratios_coefficients"

csv_array = CSV.read("#{ root }.csv", headers: true)

headers = csv_array.headers

csv_array = csv_array.sort_by do |csv_row|
   k,v = csv_row["feature_name"].split("=")
   if v[0] == "<"
      "#{k}#{ "0" * 9 }"
   elsif v[0] == ">"
      "#{k}#{ "z" * 9 }"
   else
      "#{k}#{v.to_i.to_s.rjust(9, "0")}"
   end
end

CSV.open("#{ root }_resorted.csv", "wb") do |csv_out|
   csv_out << headers
   csv_array.each do |e|
      csv_out << headers.collect {|f| e[f] }
   end
end
puts "Done"
