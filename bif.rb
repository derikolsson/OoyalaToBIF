# BIF Writer for Ruby
# by Derik Olsson <do@derik.co>
# adapted from: bcl's HMS "makeabif.py" script: https://github.com/bcl/HMS/blob/master/scripts/makebif.py

class BIF
	class Writer
		VERSION = 0

		def initialize(options = {})
			if !options[:dir].nil?
				if File.directory?(options[:dir])
					@images = Dir[File.join(options[:dir],"*.jpg")].sort!
					@interval = options.fetch(:interval, '15').to_i*1000
				else
					puts "INVALID DIRECTORY: #{options[:dir]}"
				end
			else
				puts "ABORT: Requires directory"
				exit
			end
		end

		def write_bif_file_header(file)
			file << [0x89,0x42,0x49,0x46,0x0d,0x0a,0x1a,0x0a].pack("C*")
			file << [VERSION,@images.length,@interval].pack("I3")
			file << Array.new().fill(0x00,nil,44).pack("C*")
		end

		def write_bif_index(file)
			bifTableSize = 8 + (8 * @images.length)
			frameOffset = 64 + bifTableSize
			i = 0

			@images.each do |img|
				file << [i,frameOffset].pack("I2")
				i = i + 1
				frameOffset = frameOffset + File.new(img).size
			end
			file << [0xffffffff,frameOffset].pack("I2")
		end

		def write_frames(file)
			@images.each do |img|
				file << IO.binread(img)
			end
		end

		def write(filename)
			File.open(filename, "wb") do |file|
			  write_bif_file_header(file)
			  write_bif_index(file)
			  write_frames(file)
			end
		end
	end
end