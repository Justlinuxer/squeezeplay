-----------------------------------------------------------------------------
-- strings.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.strings - string utilities

=head1 DESCRIPTION

Assorted utility functions for strings

=head1 SYNOPSIS

 -- trim a string at the first 0x00
 local trimmed = jive.util.strings.trim(some_string)

=head1 FUNCTIONS

=cut
--]]

module(..., package.seeall)


--[[

=head2 str2hex(s)

Returns a string where each char of s is replaced by its ASCII hex value.

=cut
--]]
function str2hex(s)
	local s_hex = ""
	string.gsub(
			s,
			"(.)",
			function (c)
				s_hex = s_hex .. string.format("%02X ",string.byte(c)) 
			end)
	return s_hex
end


--[[

=head2 trim(s)

Returns s trimmed down at the first 0x00 found.

=cut
--]]
function trim(s)
	local b, e = string.find(s, "%z")
	if b then
		return s:sub(1, b-1)
	else
		return s
	end
end

--[[

=head2 split(self, inSplitPattern, myString, returnTable)

Takes a string pattern and string as arguments, and an optional third argument of a returnTable

Splits myString on inSplitPattern and returns elements in returnTable (appending to returnTable if returnTable is given)

=cut
--]]

function split(self, inSplitPattern, myString, returnTable)
	if not returnTable then
		returnTable = {}
	end
	local theStart = 1
	local theSplitStart, theSplitEnd = string.find(myString, inSplitPattern, theStart)
	while theSplitStart do
		table.insert(returnTable, string.sub(myString, theStart, theSplitStart-1))
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = string.find(myString, inSplitPattern, theStart)
	end
	table.insert(returnTable, string.sub(myString, theStart))
	return returnTable
end

--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
