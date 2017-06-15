require "csv"

puts ARGV[0]
parts = ARGV[0].split(".")
ext = parts.pop

root = parts.join("")

# ARGV.each do|a|
#   puts "Argument: #{a}"
# end

puts "reading CSV file #{ root }.#{ ext }"
csv_array = CSV.read( "#{ root }.#{ ext }" , headers: true)

headers = csv_array.headers

csv_array = csv_array.sort_by do |csv_row|
   k,v = csv_row["feature"].split("=")
   if v == nil
      k
   elsif v[0] == "<"
      "#{k}#{ "0" * 9 }"
   elsif v[0] == ">"
      "#{k}#{ "z" * 9 }"
   else
      "#{k}#{v.to_i.to_s.rjust(9, "0")}"
   end
end

CSV.open("#{ root }_resorted.#{ext}", "wb") do |csv_out|
   csv_out << headers
   csv_array.each do |e|
      csv_out << headers.collect {|f| e[f] }
   end
end
puts "Done. Saved sorted version as #{ root }_resorted.#{ext}"
