#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'fileutils'

require 'ooyala-v2-api'
require 'curb'
require 'mini_magick'
require 'aws-sdk'

load 'bif.rb'

# Parse ALL the options
options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: ./OoyalaToBIF.rb -k KEY -s SECRET embed_code1 [embed_code2 embed_code3 ...]"

  opts.on("-k", "--key STRING", "Ooyala API Key") do |k|
    options[:key] = k
  end

  opts.on("-s", "--secret STRING", "Ooyala Secret") do |s|
    options[:secret] = s
  end

  opts.on("-w", "--aws STRING:STRING", "AWS AccessKeyID:SecretAccessKey") do |w|
    if w =~ /(.*)\:(.*)/
      options[:aws] = true
      creds = w.split(":")
      options[:aws_key] = creds[0]
      options[:aws_pass] = creds[1]
    else
      puts "ABORT: AWS Credentials should be entered as KEY:PASS"
    end
  end

  opts.on_tail('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

begin
  optparse.parse!(ARGV)
  if ARGV[0].nil?
    puts "ABORT: Missing embed_codes\n\n"
    puts optparse
    exit
  end
  puts options
  mandatory = [:key,:secret]
  missing = mandatory.select{ |param| options[param].nil? }
  if not missing.empty?
    puts "[ABORT] Missing required variables: #{missing.join(', ')}\n\n"
    puts optparse
    exit
  end
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  puts $!.to_s
  puts optparse
  exit
end

dir = Dir.mktmpdir
ooyala = Ooyala::API.new(options[:key],options[:secret])

# FOR EACH EMBED_CODE
ARGV.each do |asset|
  puts "\n[#{asset}] Ooyala: Contacting..."

  # Contact Ooyala
  call = ooyala.get("/v2/assets/#{asset}/generated_preview_images")
  call = call.sort_by{|hash| hash['time']}
  puts "[#{asset}] Ooyala: Responded"

  urls = {}
  i = 0
  call.each do |gpi|
    filename = File.join(dir,asset,"raw","%04d.jpg") % i
    urls[filename] = gpi['url']
    i = i + 1
  end

  FileUtils.mkdir_p(File.join(dir,asset,"raw"))

  j = 0
  print "[#{asset}] Raw Files: #{j}/#{i}"
  # Download ALL the images
  urls.each do |filename,url|
    f = open(filename,'wb')
    begin
      curl = Curl::Easy.new(url)
      curl.perform
      f.write(curl.body_str)
    rescue
      sleep(3)
      retry
    ensure
      f.close()
      j = j + 1
      print "\r[#{asset}] Raw Files: #{j}/#{i}"
    end
  end

  FileUtils.mkdir_p(File.join(dir,asset,"hd"))
  FileUtils.mkdir_p(File.join(dir,asset,"sd"))

  j = 0
  # Resize ALL the images, twice for good measure (or, just to appease HD and SD demands)
  print "\n[#{asset}] Resizing images: #{j}/#{i}"
  image_files = Dir[File.join(dir,asset,"raw","*.jpg")]
  image_files.each do |img|
    # Open Image
    image = MiniMagick::Image.open(img)

    # HD
    image.resize "320"
    image.format "jpg"
    image.write File.join(dir,asset,"hd",File.basename(img))

    # SD
    image.resize "240"
    image.format "jpg"
    image.write File.join(dir,asset,"sd",File.basename(img))

    j = j + 1
    print "\r[#{asset}] Resizing images: #{j}/#{i}"
  end

  puts "\n[#{asset}] BIFs: Building"
  # Assemble BOTH BIFs
  # HD BIF
  bif = BIF::Writer.new(dir: File.join(dir,asset,"hd"))
  bif.write(File.join(dir,"#{asset}-HD.bif"))

  # SD BIF
  bif = BIF::Writer.new(dir: File.join(dir,asset,"sd"))
  bif.write(File.join(dir,"#{asset}-SD.bif"))

  print "\r[#{asset}] BIFs: Complete!\n"
end

# Upload to S3
if options[:aws] === true
  aws = Aws::S3::Client.new(region: 'us-east-1', access_key_id: options[:aws_key], secret_access_key: options[:aws_pass])
  bifs = Dir[File.join(dir,"*.bif")]
  j = 0
  print "\nUploading to S3: #{j}/#{bifs.length}"
  bifs.each do |b|
    obj = Aws::S3::Object.new('usasfbifs',File.basename(b),{:client => aws})
    obj.upload_file(b,{:acl => "public-read"})
    j = j + 1
    print "\rUploading to S3: #{j}/#{bifs.length}"
  end
end

puts "\nCleaning Up..."
# Clean up after yourself, like your mother taught you
FileUtils.remove_entry dir
puts "Finished!\n\n"