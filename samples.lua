-----------------------------------------------------------------------------------------
-- How to try this example:
-- 1) Move this file into a new "afs_test" directory under mods and rename it "init.lua".
-- 2) Create a "depends.txt" file in the new directory with the following text:
--		nyancat
--		formspecs
-- 3) Launch your Minetest server and enable the "afs_test" mod. Then, login as usual!
-----------------------------------------------------------------------------------------

minetest.register_privilege( "uptime", "View the uptime of the server interactively" )

minetest.override_item( "nyancat:nyancat", {
	description = "System Monitor",

	can_open = function( pos, player )
		return minetest.check_player_privs( player, "uptime" )
	end,
	before_open = function( pos, node, player )
		return { is_minutes = false, is_refresh = true, pos = pos }
	end,
	on_open = function( meta, player )
		local player_name = player:get_player_name( )
		local uptime = minetest.get_server_uptime( )
		local formspec = "size[4,4]"
			.. default.gui_bg_img
			.. string.format( "label[0.5,0.5;%s %0.1f %s]",
				minetest.colorize( "#FFFF00", "Server Uptime:" ),
				meta.is_minutes and uptime / 60 or uptime,
				meta.is_minutes and "mins" or "secs"
			)
			.. "checkbox[0.5,1;is_minutes;Show Minutes;" .. tostring( meta.is_minutes ) .. "]"
			.. "checkbox[0.5,1.5;is_refresh;Auto Refresh;" .. tostring( meta.is_refresh ) .. "]"
			.. "button_exit[0.5,3;2.5,1;close;Close]"
			.. "hidden[view_count;1;number]"
			.. "hidden[view_limit;10;number]"		-- limit the number of refreshes
			.. "hidden[view_timer;1;number]"		-- auto-refresh every 1 seconds

		return formspec
	end,
	after_open = function( fs )
		if fs.meta.is_refresh == true then
			fs.start_timer( fs.meta.view_timer )
		end
	end,
	on_close = function( fs, fields )
		if fields.quit == minetest.FORMSPEC_SIGEXIT then
			print( "afs_test: Player closed formspec." )

		elseif fields.quit == minetest.FORMSPEC_SIGTIME then
			if fs.meta.view_count == fs.meta.view_limit then
				fs.destroy( )
			else
				fs.update( )
				fs.meta.view_count = fs.meta.view_count + 1
			end

		elseif fields.is_minutes then
			fs.meta.is_minutes = fields.is_minutes == "true"
			fs.update( )
			fs.reset_timer( )

		elseif fields.is_refresh then
			fs.meta.is_refresh = fields.is_refresh == "true"
			if fs.meta.is_refresh then
				fs.start_timer( fs.meta.view_timer )
			else
				fs.stop_timer( )
			end
		end
	end
} )

minetest.register_chatcommand( "uptime", {
	description = "View the uptime of the server interactively",
	func = function( name, param )
		local on_open = function( meta, player )
			local uptime = minetest.get_server_uptime( )
			local formspec = "size[4,3]"
				.. default.gui_bg_img
				.. string.format( "label[0.5,0.5;%s %0.1f %s]",
					minetest.colorize( "#FFFF00", "Server Uptime:" ),
					meta.is_minutes and uptime / 60 or uptime,
					meta.is_minutes and "mins" or "secs"
				)
				.. "checkbox[0.5,1;is_minutes;Show Minutes;" .. tostring( meta.is_minutes ) .. "]"
				.. "button_exit[0.5,2;2.5,1;close;Close]"

			return formspec
		end
		local on_close = function( fs, fields )
			if fields.quit == minetest.FORMSPEC_SIGEXIT then
				print( "afs_test: Player closed formspec." )

			elseif fields.quit == minetest.FORMSPEC_SIGTIME then
				fs.update( )

			elseif fields.is_minutes then
				fs.meta.is_minutes = fields.is_minutes == "true"
				fs.update( )
				fs.reset_timer( )
			end
		end

		local fs = FormSession( { is_minutes = false }, name, on_open, on_close )

		fs.start_timer( 1 )
	end
} )
