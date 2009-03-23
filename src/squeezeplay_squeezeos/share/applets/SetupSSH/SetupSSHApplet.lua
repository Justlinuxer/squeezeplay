
-- stuff we use
local tostring,unpack = tostring, unpack

local oo                     = require("loop.simple")
local io                     = require("io")
local os                     = require("os")
local math                   = require("math")
local string                 = require("string")

local Applet                 = require("jive.Applet")
local Checkbox               = require("jive.ui.Checkbox")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Textarea               = require("jive.ui.Textarea")
local Timer                  = require("jive.ui.Timer")
local Window                 = require("jive.ui.Window")

local log                    = require("jive.utils.log").logger("applets.setup")

module(..., Framework.constants)
oo.class(_M, Applet)


function settingsShow(self, menuItem)
	local sshEnabled = _fileMatch("/etc/inetd.conf", "^ssh")

	local window = Window("window", menuItem.text, 'settingstitle')
	local menu = SimpleMenu("menu", {
					{
						text = self:string("SSH_ENABLE"),
						icon = Checkbox("checkbox",
								function(_, isSelected)
									if isSelected then
										self:_enableSSH()
									else
										self:_disableSSH()
									end
								end,
								sshEnabled
							)
					},
				})

	window:addWidget(menu)

	self.window = window
	self.menu = menu

	self:tieAndShowWindow(window)
	return window
end


function _enableSSH(self, window)
	local ipaddr = _getIPAddress()
	local password = "1234"

	log:warn("ipaddr = ", ipaddr)
	log:warn("password = ", password)

	self.howto = Textarea("help", self:string("SSH_HOWTO", tostring(password), tostring(ipaddr)))
	self.window:addWidget(self.howto)

	-- FIXME currently the last widget added to the window has focus, until this is fixed
	-- pass events from the textarea to the menu.
	self.howto:addListener(EVENT_ALL, function(event) return Framework:dispatchEvent(self.menu, event) end)

	-- enable SSH
	_fileSub("/etc/inetd.conf", "^#ssh", "ssh")
	_sighup("/usr/sbin/inetd")

	-- set root password
	--_passwd("root", password)
end


function _disableSSH(self, window)
	if self.howto then
		self.window:removeWidget(self.howto)
		self.howto = nil
	end

	-- disable SSH
	_fileSub("/etc/inetd.conf", "^ssh", "#ssh")
	_sighup("/usr/sbin/inetd")
end


function _getIPAddress()
	local ipaddr

	local cmd = io.popen("/sbin/ifconfig")
	for line in cmd:lines() do
		ipaddr = string.match(line, "inet addr:([%d%.]+)")
		if ipaddr ~= nil and not string.match(ipaddr, "127.") then
			break
		end
	end
	cmd:close()

	return ipaddr or "?.?.?.?"
end


function _randomPassword()
	local password = {}

	for i = 1,8 do
		local n = math.random(62)
		if n < 10 then
			n = n + 48
		elseif n < 36 then
			n = n + 87
		else
			n = n + 29
		end

		password[#password + 1] = n
	end

	return string.char(unpack(password))
end


function _fileMatch(file, pattern)
	local fi = io.open(file, "r")

	for line in fi:lines() do
		if string.match(line, pattern) then
			fi:close()
			return true
		end

	end
	fi:close()

	return false
end


function _fileSub(file, pattern, repl)
	local fi = io.open(file, "r")
	local fo = io.open(file .. ".tmp", "w")

	for line in fi:lines() do
		line = string.gsub(line, pattern, repl)
		fo:write(line)
		fo:write("\n")
	end

	fi:close()
	fo:close()
	
	os.execute("/bin/mv " .. file .. ".tmp " .. file)
end


function _sighup(process)
	local pid

	local pattern = "%s*(%d+).*" .. process

	log:warn("pattern is ", pattern)

	local cmd = io.popen("/bin/ps")
	for line in cmd:lines() do
		pid = string.match(line, pattern)
		if pid then break end
	end
	cmd:close()

	if pid then
		log:warn("kill -hup ", pid)
		os.execute("kill -hup " .. pid)
	else
		log:error("cannot hup ", process)
	end
end


function _passwd(user, password)
--	os.execute("/usr/bin/chpasswd " .. user .. ":" .. password, "w")
	os.execute("echo " .. user .. ":" .. password .. "| /usr/sbin/chpasswd " , "w")
-- A check of the return of the command should be done here
-- Return is : Password for 'root' changed
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]