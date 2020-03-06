minetest.register_chatcommand( "formtest", {
	description = "Proof of concept for dynamically updating sections of forms",
	privs = { server = true },
	func = function( player_name, param )
		local count = 0
		local total = 25
		local timer

		local function get_progress( )
			return  
				"label[5.5,3.1;" .. math.floor( count / total * 100 ) .. "% Loaded]" ..
       				"box[1.8,3.0;" .. ( 3.5 * count / total ) .. ",0.6;#008888]"
		end

		local function get_message( text )
			return "label[3.0,3.1;" .. text .. "]"
		end

		local formspec = "size[7.5,5.0]" ..
			"bgcolor[#333333;true]" ..
			"box[0.0,0.0;7.5,5.0;#000000]" ..
			"image[3.0,0.4;2.5,2.5;inventory_logo.png]" ..
			"label[0.4,3.1;Progress:]" ..
			"box[1.8,3.0;3.5,0.6;#004444]" ..

			"group[message]" .. get_message( "Starting" ) .. "group_end[]" ..
			"group[progress]" .. get_progress( ) .. "group_end[]" ..
			"group[control]button[3.0,4.0;2.0,0.5;pause;Pause]group_end[]"

		local function on_close( state, player, fields )
			if fields.quit == minetest.FORMSPEC_SIGTIME then
				local groups = { progress = get_progress( ) }

				if count == 5 then
					groups.message = ""
				elseif count == 20 then
					groups.message = get_message( "Finishing" )
				elseif count == total then
					groups.message = get_message( "Complete!" )
					groups.control = "button_exit[3.0,4.0;2.0,0.5;close;Close]"
					timer.stop( )
				end

				minetest.update_form( player_name, groups )
				count = count + 1

			elseif fields.pause then
				timer.stop( )
				minetest.update_form( player_name, { control = "button[3.0,4.0;2.0,0.5;resume;Resume]" } )

			elseif fields.resume then
				timer.start( 0.6 )
				minetest.update_form( player_name, { control = "button[3.0,4.0;2.0,0.5;pause;Pause]" } )

			end
		end

		minetest.create_form( nil, player_name, formspec, on_close )
		timer = minetest.get_form_timer( player_name )
		timer.start( 0.6 )
	end
} )
