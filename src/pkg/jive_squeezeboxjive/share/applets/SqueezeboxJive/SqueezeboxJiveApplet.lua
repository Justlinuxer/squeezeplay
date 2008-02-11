
-- stuff we use
local ipairs, pcall, tostring = ipairs, pcall, tostring

local oo                     = require("loop.simple")
local string                 = require("string")
local math                   = require("math")
local os                     = require("os")
local io                     = require("io")

local jiveBSP                = require("jiveBSP")
local Watchdog               = require("jiveWatchdog")
local Wireless               = require("jive.net.Wireless")

local Applet                 = require("jive.Applet")
local Audio                  = require("jive.ui.Audio")
local Font                   = require("jive.ui.Font")
local Framework              = require("jive.ui.Framework")
local Group                  = require("jive.ui.Group")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Popup                  = require("jive.ui.Popup")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Slider                 = require("jive.ui.Slider")
local Surface                = require("jive.ui.Surface")
local Textarea               = require("jive.ui.Textarea")
local Task                   = require("jive.ui.Task")
local Tile                   = require("jive.ui.Tile")
local Timer                  = require("jive.ui.Timer")
local Checkbox               = require("jive.ui.Checkbox")
local Window                 = require("jive.ui.Window")

local debug                  = require("jive.utils.debug")
local log                    = require("jive.utils.log").logger("applets.setup")

local jnt                    = jnt
local iconbar                = iconbar
local appletManager          = appletManager

local EVENT_ACTION           = jive.ui.EVENT_ACTION
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_WINDOW_POP       = jive.ui.EVENT_WINDOW_POP
local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local EVENT_KEY_DOWN         = jive.ui.EVENT_KEY_DOWN
local EVENT_KEY_PRESS        = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD         = jive.ui.EVENT_KEY_HOLD
local EVENT_ALL_INPUT        = jive.ui.EVENT_ALL_INPUT
local EVENT_SCROLL           = jive.ui.EVENT_SCROLL
local EVENT_SWITCH           = 0x400000 -- XXXX fixme when public
local EVENT_MOTION           = 0x800000 -- XXXX fixme when public
local EVENT_WINDOW_PUSH      = jive.ui.EVENT_WINDOW_PUSH
local EVENT_VISIBLE_ALL      = jive.ui.EVENT_VISIBLE_ALL
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_UNUSED           = jive.ui.EVENT_UNUSED

local KEY_ADD                = jive.ui.KEY_ADD
local KEY_PLAY               = jive.ui.KEY_PLAY
local KEY_HOME               = jive.ui.KEY_HOME

local SW_AC_POWER            = 0
local SW_PHONE_DETECT        = 1

local squeezeboxjiveTitleStyle = 'settingstitle'
module(...)
oo.class(_M, Applet)


-- disable battery low test, useful for debugging
local CHECK_BATTERY_LOW      = true


function init(self)
	local uuid, mac

	-- read device uuid
	local f = io.popen("/usr/sbin/fw_printenv")
	if f then
		local printenv = f:read("*all")
		f:close()

		uuid = string.match(printenv, "serial#=(%x+)")
	end
	
	-- read device mac
	local f = io.popen("/sbin/ifconfig eth0")
	if f then
		local ifconfig = f:read("*all")
		f:close()

		mac = string.match(ifconfig, "HWaddr%s(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)")
	end

	log:info("uuid=", uuid)
	log:info("mac=", mac)

	jnt:setUUID(uuid, mac)

	-- watchdog timer
	self.watchdog = Watchdog:open()
	if self.watchdog then
		self.watchdog:setTimeout(30) -- 30 seconds
		local timer = Timer(10000, -- 10 seconds
				    function()
					    self.watchdog:keepAlive()
				    end)
		timer:start()
	else
		log:warn("Watchdog timer is disabled")
	end

	-- register wakeup function
	Framework:registerWakeup(function()
					 wakeup(self)
				 end)

	-- wireless
	self.wireless = Wireless(jnt, "eth0")

	iconbar.iconWireless:addTimer(5000,  -- every 5 seconds
				      function() 
					      self:update()
				      end)

	Framework:addListener(EVENT_SWITCH,
			      function(event)
				      local type = event:getType()
				      local sw,val = event:getSwitch()

				      if sw == SW_AC_POWER then
					      log:info("acpower=", val)

					      self.acpower = (val == 0)
					      self:update()

					      if self.acpower then
						      self:setPowerState("dimmed")
						      iconbar.iconBattery:playSound("DOCKING")
					      else
						      self:setPowerState("active")
					      end

				      elseif sw == SW_PHONE_DETECT then
					      if val == 1 then
						      jiveBSP.mixer(0, 97, 97)
						      jiveBSP.mixer(5, 0, 0)
					      else
						      jiveBSP.mixer(0, 0, 0)
						      jiveBSP.mixer(5, 97, 97)
					      end
				      end

				      return EVENT_CONSUME
			      end)

	-- power management
	self.powerTimer = Timer(0, function() sleep(self) end)
	Framework:addListener(EVENT_MOTION,
			      function(event) 
				      if not self.acpower then
					      wakeup(self)
				      end
				      return EVENT_UNUSED
			      end)

	Framework:addListener(EVENT_SCROLL,
			      function(event) 
				      wakeup(self)
				      return EVENT_UNUSED
			      end)

	Framework:addListener(EVENT_WINDOW_PUSH,
			      function(event) 
				      if self.powerState == "active" then
					      wakeup(self)
				      end
				      return EVENT_UNUSED
			      end)

	Framework:addListener(EVENT_KEY_PRESS,
			      function(event) 
				      local keycode = event:getKeycode()

				      -- key lock
				      if keycode == (KEY_ADD | KEY_PLAY) then
					      Framework:playSound("WINDOWSHOW")
					      lockScreen(self)
					      return EVENT_CONSUME
				      end

				      wakeup(self)
				      return EVENT_UNUSED
			      end)

	Framework:addListener(EVENT_KEY_HOLD,
		function(event) 
			local keycode = event:getKeycode()

			-- press-hold home is for power down
			if keycode == KEY_HOME then
				settingsPowerOff(self)
				return EVENT_CONSUME
			end
			return EVENT_UNUSED
		end)


	-- brightness
	self.lcdLevel = jiveBSP.ioctl(12) / 2048
	self.keyLevel = jiveBSP.ioctl(14) / 512

	-- ac or battery
	self.acpower = (jiveBSP.ioctl(23) == 0)
	if self.acpower then
		self:setPowerState("dimmed")
	else
		self:setPowerState("active")
	end

	-- headphone or speaker
	local headphone = jiveBSP.ioctl(18)
	if headphone == 1 then
		jiveBSP.mixer(0, 97, 97)
		jiveBSP.mixer(5, 0, 0)
	else
		jiveBSP.mixer(0, 0, 0)
		jiveBSP.mixer(5, 97, 97)
	end

	-- set initial state
	self:update()

	-- find out when we connect to player
	jnt:subscribe(self)

	return self
end


function notify_playerCurrent(self, player)
	local sink = function(chunk, err)
			     if err then
				     log:warn(err)
				     return
			     end

			     self:setDate(chunk.data.date)

			     -- FIXME schedule updates from server
		     end

	if player then
		player.slimServer.comet:request(sink,
					player:getId(),
					{ 'date' }
				)
	end
end


function setDate(self, date)
	-- matches date format 2007-09-08T20:40:42+00:00
	local CCYY, MM, DD, hh, mm, ss, TZ = string.match(date, "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)([-+]%d%d:%d%d)")

	log:info("CCYY=", CCYY, " MM=", MM, " DD=", DD, " hh=", hh, " mm=", mm, " ss=", ss, " TZ=", TZ)

	-- set system date
	os.execute("date " .. MM..DD..hh..mm..CCYY.."."..ss)

	-- set RTC to system time
	os.execute("hwclock -w")

	iconbar:update()
end


function update(self)
	-- ac power / battery
	if self.acpower then
		if self.batteryPopup then
			self:batteryLowHide()
		end

		local nCHRG = jiveBSP.ioctl(25)
		if nCHRG == 0 then
			iconbar:setBattery("CHARGING")
		else
			iconbar:setBattery("AC")
		end
	else
		local bat = jiveBSP.ioctl(17)
		if CHECK_BATTERY_LOW and bat < 807 then
			self:batteryLowShow()
		elseif bat < 820 then
			iconbar:setBattery("0")
		elseif bat < 834 then
			iconbar:setBattery("1")
		elseif bat < 855 then
			iconbar:setBattery("2")
		elseif bat < 875 then
			iconbar:setBattery("3")
		else
			iconbar:setBattery("4")
		end
	end

	-- wireless strength
	local quality = self.wireless:getLinkQuality()
	iconbar:setWirelessSignal(quality ~= nil and quality or "ERROR")
end


function _brightness(self, lcdLevel, keyLevel)
	local settings = self:getSettings()

	if lcdLevel ~= nil then
		-- don't update the screen when the lcd is off
		Framework:setUpdateScreen(lcdLevel ~= 0)

		self.lcdLevel = lcdLevel
		jiveBSP.ioctl(11, lcdLevel * 2048)
	end

	if keyLevel ~= nil then
		self.keyLevel = keyLevel
		jiveBSP.ioctl(13, keyLevel * 512)
	end
end


function _setBrightness(self, fade, lcdLevel, keyLevel)
	-- stop existing fade
	if self.fadeTimer then
		self.fadeTimer:stop()
		self.fadeTimer = nil
	end

	if not fade then
		_brightness(self, lcdLevel, keyLevel)
		return
	end

	-- FIXME implement smooth fade in kernel using pwm interrupts
	local steps = 30
	local lcdVal = self.lcdLevel
	local lcdInc = (lcdVal - lcdLevel) / steps
	local keyVal = self.keyLevel
	local keyInc = (keyVal - keyLevel) / steps

	if lcdVal == lcdLevel and keyVal == keyLevel then
		return
	end

	self.fadeTimer = Timer(20, function()
					   if steps == 0 then
						   if self.fadeTimer then
							   self.fadeTimer:stop()
							   self.fadeTimer = nil
						   end

						   -- ensure we hit the set value
						   _brightness(self, lcdLevel, keyLevel)
						   return
					   end

					   steps = steps - 1
					   lcdVal = lcdVal - lcdInc
					   keyVal = keyVal - keyInc
					   _brightness(self, math.ceil(lcdVal), math.ceil(keyVal))
				   end)
	self.fadeTimer:start()
end


function setBrightness(self, level)
	local settings = self:getSettings()

	if level then
		settings.brightness = level
	end

	local lcdLevel = level or settings.brightness
	local keyLevel = 0

	if self.powerState == "active" then
		keyLevel = level or settings.brightness
	end

	_setBrightness(self, false, lcdLevel, keyLevel)
end

function settingsBrightnessShow(self, menuItem)
	local window = Window("window", menuItem.text, squeezeboxjiveTitleStyle)

	local level = jiveBSP.ioctl(12) / 2047

	local slider = Slider("slider", 1, 32, level,
			      function(slider, value, done)
				      self:setBrightness(value)

				      if done then
					      window:playSound("WINDOWSHOW")
					      window:hide(Window.transitionPushLeft)
				      end
			      end)

	window:addWidget(Textarea("help", self:string("BSP_BRIGHTNESS_ADJUST_HELP")))
	window:addWidget(Group("sliderGroup", {
				       Icon("sliderMin"),
				       slider,
				       Icon("sliderMax")
			       }))

	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end


function setBacklightTimeout(self, timeout)
	local settings = self:getSettings()
	settings.dimmedTimeout = timeout

	self:setPowerState(self.powerState)	
end


function settingsBacklightTimerShow(self, menuItem)
	local window = Window("window", menuItem.text, squeezeboxjiveTitleStyle)

	local settings = self:getSettings()
	local timeout = settings.dimmedTimeout

	local group = RadioGroup()
	local menu = SimpleMenu("menu", {
					{
						text = self:string("BSP_TIMER_10_SEC"),
						icon = RadioButton("radio", group, function() self:setBacklightTimeout(10000) end, timeout == 10000),
					},
					{
						text = self:string("BSP_TIMER_20_SEC"),
						icon = RadioButton("radio", group, function() self:setBacklightTimeout(20000) end, timeout == 20000),
					},
					{
						text = self:string("BSP_TIMER_30_SEC"),
						icon = RadioButton("radio", group, function() self:setBacklightTimeout(30000) end, timeout == 30000),
					},
					{
						text = self:string("BSP_TIMER_1_MIN"),
						icon = RadioButton("radio", group, function() self:setBacklightTimeout(60000) end, timeout == 60000),
					},
					{
						text = self:string("BSP_TIMER_NEVER"),
						icon = RadioButton("radio", group, function() self:setBacklightTimeout(0) end, timeout == 0),
					},
					{
						text = self:string("DIM_WHEN_CHARGING"),
						icon = Checkbox("checkbox",
								function(obj, isSelected)
									settings.dimmedAC = isSelected
								end,
								settings.dimmedAC)
					}
				})

	window:addWidget(menu)

	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end


-- called to wake up jive
function wakeup(self)
	if self.lockedPopup then
		-- we're locked do nothing
		return
	end

	if self.powerState == "active" then
		self.powerTimer:restart()
	else
		self:setPowerState("active")
	end
end


-- called to sleep jive
function sleep(self)
	if self.powerState == "active" then
		self:setPowerState("dimmed")
	elseif self.powerState == "locked" then
		self:setPowerState("sleep")
	elseif self.powerState == "dimmed" then
		self:setPowerState("sleep")
	elseif self.powerState == "sleep" then
		self:setPowerState("suspend")
	elseif self.powerState == "suspend" then
		-- we can't go to sleep anymore
	end
end


-- set the power state and update devices
function setPowerState(self, state)
	local settings = self:getSettings()

	log:info("setPowerState=", state, " acpower=", self.acpower)
	self.powerState = state

	-- kill the timer
	self.powerTimer:stop()

	local interval = 0

	if self.acpower then
		-- charging
		self:_setCPUSpeed(true)

		if self.audioVolume ~= nil then
			log:info("Restore effect volume ", self.audioVolume)
			Audio:setEffectVolume(self.audioVolume)
			self.audioVolume = nil
		end

		if state == "active" then
			self:setBrightness()
			interval = settings.dimmedTimeout
			
		elseif state == "dimmed" then
			if settings.dimmedAC then
				self:_setBrightness(true, 8, 0)
			else
				self:setBrightness()
			end
			interval = settings.sleepTimeout

		elseif state == "sleep" then
			if settings.dimmedAC then
				self:_setBrightness(true, 0, 0)
			else
				self:setBrightness()
			end
		end

	else
		-- battery

		if state == "active" then
			self:_setCPUSpeed(true)
			self:setBrightness()

			if self.audioVolume ~= nil then
				log:info("Restore effect volume ", self.audioVolume)
				Audio:setEffectVolume(self.audioVolume)
				self.audioVolume = nil
			end

			interval = settings.dimmedTimeout

		elseif state == "locked" then
			self:_setCPUSpeed(true)
			self:setBrightness()

			if self.audioVolume ~= nil then
				log:info("Restore effect volume ", self.audioVolume)
				Audio:setEffectVolume(self.audioVolume)
				self.audioVolume = nil
			end

			self.lockedTimer:restart()
			interval = settings.dimmedTimeout

		elseif state == "dimmed" then
			self:_setCPUSpeed(true)
			self:_setBrightness(true, 8, 0)

			interval = settings.sleepTimeout

		else
			self:_setBrightness(true, 0, 0)
			self:_setCPUSpeed(false)

			if not self.audioVolume then
				self.audioVolume = Audio:getEffectVolume()
				log:info("Store effect volume ", self.audioVolume)
				Audio:setEffectVolume(0)
			end

			if state == "sleep" then
				interval = settings.suspendTimeout

			elseif state == "suspend" then
				-- XXXX
				-- self:_suspend()
			end
		end
	end

	if interval > 0 then
		self.powerTimer:setInterval(interval)
		self.powerTimer:start()
	end
end


function lockScreen(self)
	-- lock
	local popup = Popup("popupIcon")
	-- FIXME change icon and text
	popup:addWidget(Icon("iconLocked"))
	popup:addWidget(Label("text", self:string("BSP_SCREEN_LOCKED")))
	popup:addWidget(Textarea("help", self:string("BSP_SCREEN_LOCKED_HELP")))
	self:tieAndShowWindow(popup)

	self:setPowerState("locked")

	self.lockedPopup = popup
	self.lockedTimer = Timer(2000,
				 function()
					 self:_setBrightness(true, 0, 0)
					 self:_setCPUSpeed(false)
				 end,
				 true)

	self.lockedListener = 
		Framework:addListener(EVENT_KEY_DOWN | EVENT_KEY_PRESS,
				      function(event)
					      if event:getType() == EVENT_KEY_PRESS and event:getKeycode() == (KEY_ADD | KEY_PLAY) then
						      popup:playSound("WINDOWHIDE")
						      unlockScreen(self)
						      return EVENT_CONSUME
					      end

					      self:setPowerState("locked")
					      return EVENT_CONSUME
				      end,
				      true)
end


function unlockScreen(self)
	if self.lockedPopup then
		-- unlock
		Framework:removeListener(self.lockedListener)
		self.lockedTimer:stop()
		self.lockedPopup:hide()

		self.lockedPopup = nil
		self.lockedTimer = nil
		self.lockedListener = nil
	end
end


function batteryLowShow(self)
	if self.batteryPopup then
		return
	end

	log:info("batteryLowShow")

	local popup = Popup("popupIcon")

	popup:addWidget(Icon("iconBatteryLow"))
	popup:addWidget(Label("text", self:string("BATTERY_LOW")))

	-- make sure this popup remains on screen
	popup:setAllowScreensaver(false)
	popup:setAlwaysOnTop(true)
	popup:setAutoHide(false)

	self.batteryPopup = popup

	popup:addTimer(30000,
		       function()
			       self:_powerOff()
		       end,
		       true)

	-- consume all key and scroll events
	self.batteryListener
		= Framework:addListener(EVENT_ALL_INPUT,
					function(event)
						Framework.wakeup()

						-- allow power off
						if event:getType() == EVENT_KEY_HOLD and event:getKeycode() == KEY_HOME then
							self:settingsPowerOff()
						end
						return EVENT_CONSUME
					end,
					true)

	-- make sure the display is on
	self:setBrightness()

	self:tieAndShowWindow(popup)
end


function batteryLowHide(self)
	log:info("batteryLowHide")

	Framework:removeListener(self.batteryListener)
	self.batteryPopup:hide()

	self.batteryPopup = nil
	self.batteryListener = nil
end


function settingsPowerDown(self, menuItem)
        log:debug("powerDown menu")
	-- add window
	local window = Window("window", menuItem.text, 'settingstitle')
	window:addWidget(Textarea("help", self:string("POWER_DOWN_HELP")))

	local menu = SimpleMenu("menu")
	window:addWidget(menu)


	local items = {
		{ 
			text = self:string("POWER_DOWN_CANCEL"),
			sound = "WINDOWHIDE",
			callback = function() window:hide() end
		},
		{ 
			text = self:string("POWER_DOWN_CONFIRM"),
			sound = "SELECT",
			callback = function() settingsPowerOff(self) end
		}
	}
	menu:setItems(items)

        self:tieAndShowWindow(window)
        return window
end


function settingsPowerOff(self)
	-- disconnect from SqueezeCenter
	local slimDiscovery = appletManager:loadApplet("SlimDiscovery")
	slimDiscovery.serversObj:disconnect()

	local popup = Popup("popupIcon")

	popup:addWidget(Icon("iconPower"))
	popup:addWidget(Label("text", self:string("GOODBYE")))

	-- make sure this popup remains on screen
	popup:setAllowScreensaver(false)
	popup:setAlwaysOnTop(true)
	popup:setAutoHide(false)

	-- we're shutting down, so prohibit any key presses or holds
	Framework:addListener(EVENT_ALL_INPUT,
			      function () 
				      return EVENT_CONSUME
			      end,
			      true)

	popup:addTimer(4000, 
		function()
			self:_powerOff()
		end,
		true
	)

	self:tieAndShowWindow(popup)

	popup:playSound("SHUTDOWN")
end


function _setCPUSpeed(self, fast)
	local filename = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"

	-- 200MHZ or 50MHz
	local speed = fast and 200000 or 50000

	log:info("Set CPU speed ", speed)
	local fh, err = io.open(filename, "w")
	if err then
		log:warn("Can't write to  ", filename)
		return
	end

	fh:write(speed)
	fh:close()
end


function _suspendTask(self)
	-- check existing network config
	local status = self.wireless:t_wpaStatus()
	local zeroconf = string.match(status.ip_address, "^169.254.") ~= nil

	-- suspend
	os.execute("/etc/init.d/suspend")

	-- wake up power state
	self:wakeup()

	-- start timer to resume this task every second
	self.suspendPopup:addTimer(1000,
		function()
			if self.suspendTask then
				self.suspendTask:addTask()
			end
		end)

	while true do
		local status = self.wireless:t_wpaStatus()

		-- network connected?
		log:info("resume ip=", status.ip_address, " zeroconf=", zeroconf)
		if status.wpa_state == "COMPLETED" and status.ip_address and (not string.match(status.ip_address, "^169.254.") or zeroconf) then

			-- force reconnections
			jnt:notify("networkConnected")

			-- close popup
			self.suspendPopup:hide()

			-- wake up
			self:wakeup()

			self.suspendPopup = nil
			self.suspendTask = nil

			return
		end

		Task:yield(false)
	end
end


function _suspend(self)
	log:info("Suspend ...")

	-- draw popup ready for resume
	local popup = Popup("popupIcon")
	popup:setAllowScreensaver(false)
	popup:setAlwaysOnTop(true)
	popup:setAutoHide(false)

	popup:addWidget(Icon("iconConnecting"))
	popup:addWidget(Label("text", self:string("PLEASE_WAIT")))

	-- ignore all events
	popup:addListener(EVENT_ALL_INPUT,
			   function(event)
				   return EVENT_CONSUME
			   end)

	popup:show(Window.transitionNone)
	self.suspendPopup = popup

	-- make sure the cpu is fast when we resume
	self:_setCPUSpeed(true)

	-- enable frame updates
	Framework:setUpdateScreen(true)

	-- force popup to be drawn to the framebuffer
	Framework:updateScreen()

	-- start suspend task
	self.suspendTask = Task("networkStatus", self, _suspendTask)
	self.suspendTask:addTask()
end


function _powerOff(self)
	log:info("Poweroff begin")

	self:_setBrightness(true, 0, 0)

	-- power off when lcd is off, or after 1 seconds
	local tries = 10
	self.powerOffTimer = Timer(100,
				   function()
					   if self.lcdLevel == 0 or tries  == 0 then
						   log:info("Poweroff on")
						   os.execute("/sbin/poweroff")
					   else
						   tries = tries - 1
					   end
				   end)
	self.powerOffTimer:start()
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
