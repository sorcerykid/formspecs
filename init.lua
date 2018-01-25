--------------------------------------------------------
-- Minetest :: ActiveFormspecs Mod v3.0a (formspecs)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2016-2018, Leslie Ellen Krause
--
-- ./games/just_test_tribute/mods/formspecs/init.lua
--------------------------------------------------------

print( "Loading ActiveFormspecs Mod" )

minetest.FORMSPEC_SIGEXIT = true	-- player clicked exit button or pressed esc key (boolean for backward compatibility)
minetest.FORMSPEC_SIGQUIT = 1		-- player logged off
minetest.FORMSPEC_SIGKILL = 2		-- player was killed
minetest.FORMSPEC_SIGTERM = 3		-- server is shutting down
minetest.FORMSPEC_SIGPROC = 4		-- procedural closure
minetest.FORMSPEC_SIGTIME = 5		-- timeout reached

local afs = { }		-- obtain localized, protected namespace

afs.forms = { }
afs.timers = { }
afs.session_id = 0
afs.session_seed = math.random( 0, 65535 )
afs.rtime = 1.0

afs.stats = { active = 0, opened = 0, closed = 0 }

afs.stats.on_open = function ( self )
	self.active = self.active + 1
	self.opened = self.opened + 1
end

afs.stats.on_close = function ( self )
	self.active = self.active - 1
	self.closed = self.closed + 1
end

-----------------------------------------------------------------
-- trigger callbacks at set intervals within timer queue
-----------------------------------------------------------------

minetest.register_globalstep( function( dtime )
	afs.rtime = afs.rtime - dtime

	-- rate-limiting of timers to once per second seems optimal

	if afs.rtime <= 0.0 then
		local idx = #afs.timers

		local curtime = os.time( )

		while idx > 0 do
			local self = afs.timers[ idx ]

                	if curtime >= self.exptime then
				self.counter = self.counter + 1
				self.exptime = curtime + self.form.timeout

				self.overrun = -afs.rtime
				self.form:on_close( { quit = minetest.FORMSPEC_SIGTIME } )
				self.form.newtime = curtime
				self.overrun = 0.0
        	        end
			idx = idx - 1
	        end

		afs.rtime = 1.0
	end
end )

-----------------------------------------------------------------
-- create attached formspecs during node registration
-----------------------------------------------------------------

local on_rightclick = function( pos, node, player )
	local nodedef = minetest.registered_nodes[ node.name ]

	if not nodedef.can_open or nodedef.can_open( pos, player ) == true then
		local meta = nodedef.before_open and 
			nodedef.before_open( pos, node, player ) or 
			{ pos = pos, node = node }

		local form = FormSession( meta, player:get_player_name( ), nodedef.on_open, nodedef.on_close )
		
		form.origin = minetest.pos_to_string( pos )

		if nodedef.after_open then
			nodedef.after_open( form )
		end
	end
end

local old_register_node = minetest.register_node
local old_override_item = minetest.override_item

minetest.register_node = function ( name, def )
	if def.on_open and not def.on_rightclick then
		def.on_rightclick = on_rightclick
	end
	old_register_node( name, def )
end

minetest.override_item = function ( name, def )
	if minetest.registered_nodes[ name ] and def.on_open then
		def.on_rightclick = on_rightclick
	end
	old_override_item( name, def )
end

-----------------------------------------------------------------
-- trigger callbacks after every form submission
-----------------------------------------------------------------

minetest.register_on_player_receive_fields( function( player, formname, fields )
	local player_name = player:get_player_name( )
	local form = afs.forms[ player_name ]

	-- perform a basic sanity check, since these shouldn't technically occur
	if not form or player ~= form.player or formname ~= form.name then return end

	form.newtime = os.time( )
	form:on_close( fields )

	-- revoke current session when formspec is closed
	if fields.quit then
		form.stop_timer( )

		afs.stats:on_close( )
		afs.forms[ player_name ] = nil
	end
end )

-----------------------------------------------------------------
-- create form session object with benchmarking hooks
-----------------------------------------------------------------

FormSession = function( meta, player_name, on_open, on_close, timeout )
	if not player_name or not on_open then return end

	if afs.forms[ player_name ] then
		local form = afs.forms[ player_name ]

		form.stop_timer( )
		form:on_close( { quit = minetest.FORMSPEC_SIGPROC } )

		afs.stats:on_close( )
	end

	local self = { }

	-- optional benchmarking hooks

	if minetest.setting_getbool( "enable_formspecs_benchmarking" ) == true then
		local get_clock = minetest.get_us_time
		local ptime = { on_open = 0.0, on_close = 0.0 }

		self.on_open = function( meta, player )
			local t = get_clock( )
			local v = on_open( meta, player )
			ptime.on_open = ptime.on_open + ( get_clock( ) - t ) / 1000000.0
			return v
		end
		self.on_close = function( form, fields )
			local t = get_clock( )
			on_close( form, fields )
			ptime.on_close = ptime.on_close + ( get_clock( ) - t ) / 1000000.0
		end
		self.get_proctime = function( )
			return { on_open = ptime.on_open, on_close = ptime.on_close }
		end
	else
		self.on_open = on_open
		self.on_close = on_close or function ( ) end
		self.get_proctime = function( )
			return { on_open = 0.0, on_close = 0.0 }
		end
	end

	afs.session_id = afs.session_id + 1

	self.id = afs.session_id
	self.player = minetest.get_player_by_name( player_name )
	self.name = minetest.get_password_hash( player_name, afs.session_seed + afs.session_id )
	self.origin = string.match( debug.getinfo( 2 ).source, ".*[/\\]mods[/\\](.-)[/\\]" ) or "?"
	self.meta = meta or { }

	self.counter = 0
	self.oldtime = os.time( )
	self.newtime = self.oldtime

	-- declare private methods

	local parse_metadata = function( formspec )
		return string.gsub( formspec, "hidden%[(.-);(.-)%]", function( key, value )
			if self.meta[ key ] == nil then
				local data, type = string.match( value, "^(.-);(.-)$" )
					-- parse according to specified data type
				if type == "string" or type == "" then
					self.meta[ key ] = data
				elseif type == "number" then
					self.meta[ key ] = tonumber( data )
				elseif type == "boolean" then
					self.meta[ key ] = ( { ["1"] = true, ["0"] = false, ["true"] = true, ["false"] = false } )[ data ]
				elseif type == nil then
					self.meta[ key ] = value	-- default to string, if no data type specified
				end
			end
			return ""	-- strip hidden elements prior to showing formspec
		end )
	end

	-- declare public methods

	self.is_active = function ( )
		return afs.forms[ player_name ] == self
	end
	self.get_lifetime = function ( )
		if afs.forms[ player_name ] ~= self then return 0 end

		return os.time( ) - self.oldtime
	end
	self.get_idletime = function ( )
		if afs.forms[ player_name ] ~= self then return 0 end

		return os.time( ) - self.newtime or nil
	end
	self.get_timer_state = function ( )
		if afs.forms[ player_name ] ~= self and not self.timeout then return end

		for i, v in ipairs( afs.timers ) do
			local curtime = os.time( )

			if v.form == self then
				return { elapsed = curtime - v.oldtime, timeout = v.exptime - curtime, overrun = -v.overrun, counter = v.counter }
			end
		end
	end
	self.start_timer = function ( timeout )
		if afs.forms[ player_name ] == self and not self.timeout and timeout > 0 then
			local curtime = os.time()

			self.timeout = timeout
			table.insert( afs.timers, { form = self, counter = 0, oldtime = curtime, exptime = curtime + math.ceil( timeout ), overrun = 0.0 } )
		end
	end
	self.stop_timer = function ( )
		if afs.forms[ player_name ] ~= self or not self.timeout then return end

		self.timeout = nil

		for i, v in ipairs( afs.timers ) do
			if v.form == self then
				table.remove( afs.timers, i )
	                        return
			end
		end
	end
	self.reset_timer = function ( )
		if afs.forms[ player_name ] ~= self or not self.timeout then return end

		for i, v in ipairs( afs.timers ) do
			if v.form == self then
				v.exptime = os.time( ) + math.ceil( self.timeout )
	                        return
			end
		end
	end
	self.update = function ( )
		if afs.forms[ player_name ] ~= self then return end

		local formspec = self.on_open( self.meta, self.player )

		minetest.show_formspec( player_name, self.name, parse_metadata( formspec ) )
		self.counter = self.counter + 1
	end
	self.destroy = function ( )
		if afs.forms[ player_name ] ~= self then return end

		minetest.close_formspec( player_name, self.name )
		self:on_close( { quit = minetest.FORMSPEC_SIGPROC } )
		self.stop_timer( )

		afs.stats:on_close( )
		afs.forms[ player_name ] = nil
	end

	afs.stats:on_open( )
	afs.forms[ player_name ] = self

	self.update( )

	if timeout then 
		self.start_timer( timeout )
	end

	return self
end

-----------------------------------------------------------------
-- signal callbacks after unexpected form termination
-----------------------------------------------------------------

minetest.register_on_leaveplayer( function( player, is_timeout )
	local player_name = player:get_player_name( )
	local form = afs.forms[ player_name ]

	if form then
		form.newtime = os.time( )	
		form:on_close( { quit = minetest.FORMSPEC_SIGQUIT } )
		form.stop_timer( )

		afs.stats:on_close( )
		afs.forms[ player_name ] = nil
	end
end )

minetest.register_on_dieplayer( function( player )
	local player_name = player:get_player_name( )
	local form = afs.forms[ player_name ]

	if form then
		form.newtime = os.time( )	
		form:on_close( { quit = minetest.FORMSPEC_SIGKILL } )
		form.stop_timer( )

		afs.stats:on_close( )
		afs.forms[ player_name ] = nil
	end
end )

minetest.register_on_shutdown( function( )
	for _, form in pairs( afs.forms ) do
		form:on_close( { quit = minetest.FORMSPEC_SIGTERM } )
		form.stop_timer( )

		afs.stats:on_close( )
	end
	afs.forms = { }
end )

minetest.register_chatcommand( "fs", {
        description = "Show realtime information about form sessions",
	privs = { server = true },
        func = function( name, param )
		local page_idx = 1
		local page_size = 10
		local sorted_forms

		local get_sorted_forms = function( )
			local f = { }
			for k, v in pairs( afs.forms ) do
				table.insert( f, v )
			end
			table.sort( f, function( a, b ) return a.id < b.id end )
			return f
		end
		local on_open = function( meta, player )
			local uptime = minetest.get_server_uptime( )

			local formspec = "size[11.5,7.5]"
				.. default.gui_bg
				.. default.gui_bg_img

				.. "label[0.1,6.7;ActiveFormspecs v3.0]"
				.. string.format( "label[0.1,0.0;%s]label[0.1,0.5;%d min %02d sec]",
					minetest.colorize( "#888888", "uptime:" ), math.floor( uptime / 60 ), uptime % 60 )
				.. string.format( "label[7.6,0.0;%s]label[7.6,0.5;%d]",
					minetest.colorize( "#888888", "active" ), afs.stats.active )
				.. string.format( "label[8.9,0.0;%s]label[8.9,0.5;%d]",
					minetest.colorize( "#888888", "opened" ), afs.stats.opened )
				.. string.format( "label[10.2,0.0;%s]label[10.2,0.5;%d]",
					minetest.colorize( "#888888", "closed" ), afs.stats.closed )

				.. string.format( "label[0.5,1.5;%s]label[3.0,1.5;%s]label[5.2,1.5;%s]label[6.4,1.5;%s]label[7.6.0,1.5;%s]label[8.9,1.5;%s]label[10.2,1.5;%s]",
					minetest.colorize( "#888888", "player" ), 
					minetest.colorize( "#888888", "origin" ), 
					minetest.colorize( "#888888", "counter" ), 
					minetest.colorize( "#888888", "timeout" ), 
					minetest.colorize( "#888888", "proctime" ), 
					minetest.colorize( "#888888", "idletime" ), 
					minetest.colorize( "#888888", "lifetime" )
				)

				.. "box[0,1.2;11.2,0.1;#111111]"
				.. "box[0,6.2;11.2,0.1;#111111]"

			local num = 0
			for idx = ( page_idx - 1 ) * page_size + 1, math.min( page_idx * page_size, #sorted_forms ) do
				local form = sorted_forms[ idx ]

				local idletime = form.get_idletime( )
				local lifetime = form.get_lifetime( )
				local proctime = form.get_proctime( )
				local player_name = form.player:get_player_name( )

				local vert = 2.0 + num * 0.5

				formspec = formspec 
					.. string.format( "button[0.1,%0.1f;0.5,0.3;del:%s;x]", vert + 0.1, player_name )
					.. string.format( "label[0.5,%0.1f;%s]", vert, player_name )
					.. string.format( "label[3.0,%0.1f;%s]", vert, form.origin )
					.. string.format( "label[5.2,%0.1f;%d]", vert, form.counter )
					.. string.format( "label[6.4,%0.1f;%ds]", vert, form.timeout or 0 )
					.. string.format( "label[7.6,%0.1f;%0.4fs]", vert, proctime.on_open + proctime.on_close )
					.. string.format( "label[8.9,%0.1f;%dm %02ds]", vert, math.floor( idletime / 60 ), idletime % 60 )
					.. string.format( "label[10.2,%0.1f;%dm %02ds]", vert, math.floor( lifetime / 60 ), lifetime % 60 )
				num = num + 1
			end

			formspec = formspec
				.. "button[8.4,6.5;1,1;prev;<<]"
				.. string.format( "label[9.4,6.7;%d of %d]", page_idx, math.max( 1, math.ceil( #sorted_forms / page_size ) ) )
				.. "button[10.4,6.5;1,1;next;>>]"

			return formspec
		end
		local on_close = function( fs, fields )
			if fields.quit == minetest.FORMSPEC_SIGTIME then
				sorted_forms = get_sorted_forms( )
				fs.update( )
			elseif fields.prev and page_idx > 1 then
				page_idx = page_idx - 1
				fs.update( )
			elseif fields.next and page_idx < #sorted_forms / page_size then
				page_idx = page_idx + 1
				fs.update( )
			else
				local player_name = string.match( next( fields, nil ), "del:(.+)" )
				if player_name and afs.forms[ player_name ] then
					afs.forms[ player_name ].destroy( )
				end
			end
		end

		sorted_forms = get_sorted_forms( )

		FormSession( nil, name, on_open, on_close, 3 )

		return true
	end,
} )
