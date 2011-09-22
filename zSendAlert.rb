#!/usr/bin/ruby

# Copyright (C) 2011 - Gareth Llewellyn
# 
# This file is part of Anfon - https://github.com/NetworksAreMadeOfString/anfon
#
# A drop in replacement for the Zenoss Pager script written in ruby allowing 
# interfacing to Clickatell, PagerDuty and others 
# 
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
# 
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>

require 'open-uri'
require 'uri'
require 'rubygems'

#Credentials for Clickatell
clickatell_user     = 'test'
clickatell_password = 'test'
clickatell_id       = 'test'
clickatell_from     = 'test'

#PagerDuty API Key
pagerduty_key       = false

#MySQL credentials for limiting texts sent
mysql_user          = 'test'
mysql_passsword     = 'test'
mysql_enabled       = false

#Program variables
recipient = ''
message = ''
argc = 0
maxSMS = 20
sentSMS = 0

#Extra requires if we need them
if pagerduty_key
  require 'net/http'
  require 'net/https'
  require 'json'
end
if mysql_enabled
  require 'mysql'
end

#-------------------------Start with the messaging of people
#Get the SMS number
ARGV.each do|a|
  if argc == 0
    recipient = a
    argc = 1
  end #I don't care about any other arguments
end

#Grab the text from stdin (the actual message from Zenoss)
STDIN.each_line do |line|
  message << line
end

#Check for max SMS sent if sql is enabled for storing the details
if mysql_enabled
  my = Mysql.new('127.0.0.1',mysql_user, mysql_passsword, 'sms', 3307)
  st = my.prepare("SELECT count(1) from `sms` WHERE `sent` = 'yes' AND `when` > DATE_SUB(NOW(),INTERVAL 1 HOUR)")
  st.execute
  sentSMS = st.fetch[0]
else
  sentSMS = 0
end

#This is just to make sure we don't waste 90,000,000 SMS credits due to something crazy happening
if sentSMS > maxSMS
  puts "Too many SMS's sent (#{sentSMS} / #{maxSMS})"
  st.close
else
  if mysql_enabled
    message << " #{sentSMS}/#{maxSMS}"
  end
  
  safemessage = URI.escape(message, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
  if recipient != '0000'
    http = Net::HTTP.new('api.clickatell.com', 80)
    http.use_ssl = false
    path = "/http/sendmsg?user=#{clickatell_user}&password=#{clickatell_password}&api_id=#{clickatell_id}&to=#{recipient}&text=#{safemessage}&from=#{clickatell_from}&concat=2"
    http.get(path)
  end
  
  #If mysql is enabled add an entry
  if mysql_enabled
    sentSMS += 1
    st.prepare("INSERT INTO sms (recipient,message,sent,response) VALUES (?,?,?,?)")
    st.execute(recipient,message,'yes', 200)
    st.close
  end
  
  #If PagerDuty is enabled and the recipient number is our specified one (this is specific to our use case)
  #then call the API via HTTP POST
  if pagerduty_key && recipient == '0000'
    http = Net::HTTP.new('events.pagerduty.com', 443)
    http.use_ssl = true
    path = '/generic/2010-04-15/create_event.json'
    data = "{\"service_key\": \"#{pagerduty_key}\", \"event_type\": \"trigger\",\"description\": \"#{message}\"}"
    headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
    resp, data = http.post(path, data, headers)
    #puts 'Code = ' + resp.code
    #puts 'Message = ' + resp.message
    #resp.each {|key, val| puts key + ' = ' + val}
    #puts data
  end
end
