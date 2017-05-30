require "csv"

input_filename = "zipcode_gps.csv"
center_zip = "19104"
output_filename = "zipcode_distances_from_#{ center_zip }.csv"

@zipcode_gps = CSV.read(input_filename, {headers: true})

# ZIP,LAT,LNG 

def degreesToRadians(degrees) 
  degrees * 3.14159265359 / 180;
end

def distanceInKmBetweenEarthCoordinates(lat1, lon1, lat2, lon2) 
   earthRadiusKm = 6371;

   dLat = degreesToRadians(lat2-lat1);
   dLon = degreesToRadians(lon2-lon1);

  lat1 = degreesToRadians(lat1);
  lat2 = degreesToRadians(lat2);

   a = Math.sin(dLat/2) * Math.sin(dLat/2) +
          Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2); 
   c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
  return earthRadiusKm * c;
end

puts "Calculating distances for GPS coordinates for #{ center_zip }"
center = @zipcode_gps.select {|e| e["ZIP"] == center_zip}.first
center_lat = center["LAT"].to_f
center_lng = center["LNG"].to_f


CSV.open(output_filename, "wb") do |csv|
  csv << ["ZIP", "DIST_KM"]
  @zipcode_gps.each do |e|
    csv << [
      e["ZIP"],
      distanceInKmBetweenEarthCoordinates( e["LAT"].to_f , e["LNG"].to_f, center_lat, center_lng).round(2)
    ]
  end
end  

puts "Saved #{ output_filename }"
