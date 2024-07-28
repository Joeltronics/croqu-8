pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- By Joel Geddert
-- License: CC BY-NC-SA 4.0

--
-- Game core consts
--

DEBUG = true

BALL_R = 2.25
BALL_D = 2 * BALL_R
BALL_D2 = BALL_D*BALL_D

BALL_POLE_D = BALL_R + 0.125
BALL_POLE_D2 = BALL_POLE_D*BALL_POLE_D

MOVING_COOLDOWN_FRAMES = 60
SHOT_POWER_METER_RATE = 1/64
SHOT_POWER_METER_FALL_RATE = -1/32
SHOT_POWER_ERR_MAX_POWER = 5/360
SHOT_POWER_ERR_OVER = 15/360

ANGLE_STEP = 1/256

SQRT_MAX = sqrt(32767) - 0.001

--
-- Field dimensions & wicket locations
--

ROUGH = 16

WIDTH, HEIGHT = 384 + 2*ROUGH, 192+2*ROUGH

CX = WIDTH \ 2
CY = HEIGHT \ 2

PX = 32
W1X = 64
W2X = 96
W3X = CX - 48
WY = CY - 48

WICKETS = {
	{PX, CY, pole=true},
	{W1X, CY},
	{W2X, CY},
	{W3X, HEIGHT - WY},
	{CX, CY},
	{WIDTH - W3X, HEIGHT - WY},
	{WIDTH - W2X, CY},
	{WIDTH - W1X, CY},
	{WIDTH - PX, CY, pole=true},
	{WIDTH - W1X, CY, reverse=true, hidden=true},
	{WIDTH - W2X, CY, reverse=true, hidden=true},
	{WIDTH - W3X, WY, reverse=true},
	{CX, CY, reverse=true, hidden=true},
	{W3X, WY, reverse=true},
	{W2X, CY, reverse=true, hidden=true},
	{W1X, CY, reverse=true, hidden=true},
	{PX, CY, reverse=true, pole=true, hidden=true},
}
WICKET_COLLISION_POINTS = {}  -- Populated at init

--
-- Physics consts
--

COLLISION_CHECK_DIVISIONS = 4

SHOT_V_MAX = 1.5
SHOT_V_MIN = 0.0625

DRAG = 1 - 1/128
DRAG_ROUGH = 1 - 1/8
V2_STOP_THRESH = 1/1024

VELOCITY_REDUCE_BALL_COLLISION = 1 - 1/64
VELOCITY_REDUCE_POLE_COLLISION = 0.5
VELOCITY_REDUCE_WICKET_COLLISION = 0.25

BALL_STOP_RANDOM_MOVEMENT = 0.25

--
-- AI logic consts
--

AI_TARGET_PAST_WICKET_POLE_DISTANCE = 6
AI_TARGET_PAST_BALL_DISTANCE = 8
AI_TARGET_AHEAD_OF_WICKET_DISTANCE = 8
AI_CLEAR_SHOT_MIN_BALL_DISTANCE = 64
AI_CLEAR_SHOT_MIN_BALL_DISTANCE_SQUARED = AI_CLEAR_SHOT_MIN_BALL_DISTANCE
AI_TARGET_BALL_MAX_WEIGHTED_DISTANCE = 128
AI_TARGET_BALL_MAX_WEIGHTED_DISTANCE_EASY_SHOT = 24

--
-- Graphics Consts
--

TITLE_SCREEN_STRIPES = 3 -- The actual number is 2*TITLE_SCREEN_STRIPES + 1

DEFAULT_PALT = 0b0001000000000000

DISPLAY_PALETTE = {
	[13]=-5, -- Indigo --> Jade
	[15]=-4, -- Peach --> Royal Blue
}

STATUS_BAR_WIDTH = 8

ROUGH_FILLP = 0b0101010110101010
ROUGH_COLOR = 0x35

PALETTES = {
	-- main, dark, light
	{[8]=15, [2]=1, [14]=12}, -- Blue
	{[8]=8, [2]=2, [14]=14}, -- Red
	{[8]=0, [2]=1, [14]=5}, -- Black
	{[8]=10, [2]=9, [14]=6}, -- Yellow
	{[8]=11, [2]=3, [14]=6}, -- Green
	{[8]=9, [2]=4, [14]=10}, -- Orange
}

SHOT_POWER_COLORS = {1, 12, 11, 10, 9}

--
-- Globals
--

num_players = 6
num_players_finished = 0

game_started = false
game_finished = false

players = {}
balls = {}

player_idx = 1

camera_x = 64
camera_y = CY

-- Camera will look ahead toward next wicket when this is set
camera_look_ahead = true

shot_angle = 0
shot_power = 0
shot_power_change = 0
shot_power_over = false

moving_cooldown = 0

debug_last_dv = nil

debug_pause_physics = false
debug_no_draw_tops = false
debug_draw_primitives = false
debug_increase_shot_pointer_length = false

--
-- Utility functions
--

function pelogen_tri_low(l,t,c,m,r,b,col)
	-- By shiftalow, with some slight changes (CC4-BY-NC-SA)
	while t>m or m>b do
		l,t,c,m=c,m,l,t
		while m>b do
			c,m,r,b=r,b,c,m
		end
	end
	local e,j=l,(r-l)/(b-t)
	while m do
		local i=(c-l)/(m-t)
		for t=flr(t),flr(m)-1 do
			rectfill(l,t,e,t,col)
			l+=i
			e+=j
		end
		l,t,m,c,b=c,m,b,r
	end
	pset(r,t,col)
end

function reset_palette()
	pal()
	palt(DEFAULT_PALT)
end

function print_centered(text, x, y, col)
	local t = '' .. text
	print(t, x - 2*#t, y, col)
end

function round(val)
	return flr(val + 0.5)
end

function line_round(x1, y1, x2, y2, col)
	line(round(x1), round(y1), round(x2), round(y2), col)
end

function clip_num(val, minval, maxval)
	return max(minval, min(maxval, val))
end

function lerp(a, b, t)
	-- return a + t * (b - a)
	return (1 - t) * a + t * b
end

function lerp_round(a, b, t)
	return round(lerp(a, b, t))
end

function distance(dx, dy)
	-- Calculate distance, overflow-safe
	-- Exact distance when close, approximate distance when further

	dx = abs(dx)
	dy = abs(dy)

	local d

	if (dx > 127 or dy > 127) then
		d = dx + dy
	else
		d = sqrt(dx*dx + dy*dy)
	end

	if (d < 0) d = 32767

	return d
end

function distance_squared(dx, dy)
	-- Calculate distance squared, overflow-safe
	-- On overflow, returns 32767
	dx, dy = abs(dx), abs(dy)

	if (dx >= SQRT_MAX or dy >= SQRT_MAX) return 32767

	local dx2, dy2 = dx*dx, dy*dy
	local d2 = dx2 + dy2
	if (d2 < dx2 or d2 < dy2) return 32767

	assert(d2 >= 0)

	return d2
end

function sort_z(items)
	-- Bubblesort items by z value, or y value if z is not found
	for idx1 = 1,#items do
		local any_swapped = false
		for idx2 = 1,#items-1 do
			local item1 = items[idx1]
			local item2 = items[idx2]
			if ((item1.z or item1.y) < (item2.z or item2.y)) then
				items[idx1] = item2
				items[idx2] = item1
				any_swapped = true
			end
		end
		if (not any_swapped) return
	end
end

function shot_power_color()
	if (shot_power <= 0) return 0
	if (shot_power_over) return 8
	return SHOT_POWER_COLORS[clip_num(flr(shot_power * #SHOT_POWER_COLORS) + 1, 1, #SHOT_POWER_COLORS)]
end

function update_camera()
	-- TODO: If player's ball isn't moving but another is, make camera follow that one instead?
	local player = players[player_idx]
	if (not player.ball) return

	camera_x = player.ball.x
	camera_y = player.ball.y

	local next_wicket = WICKETS[player.last_wicket_idx + 1]
	if camera_look_ahead and next_wicket then
		camera_x = clip_num(lerp(camera_x, next_wicket[1], 0.5), camera_x - 32, camera_x + 32)
		camera_y = clip_num(lerp(camera_y, next_wicket[2], 0.5), camera_y - 32, camera_y + 32)
	end
end

--
-- Physics
--

function dotpart(vx, vy, nx, ny)
	-- From pico pool by nusan (CC4-BY-NC-SA)
	local dot = vx*nx + vy*ny
	vx = vx - dot*nx
	vy = vy - dot*ny
	return vx, vy
end

function calc_overlap(dx, dy, sum_radius)
	local d = distance(dx, dy)
	local overlap = max(0, sum_radius + 0.25 - d) / d
	return overlap, d
end

function ball_collisions()
	-- Partially based on pico pool by nusan (CC4-BY-NC-SA)

	local any_collisions, current_player = false, players[player_idx]

	if (current_player.finish_position) return false

	for idx1 = 1, #balls do
		local b1 = balls[idx1]
		for idx2 = idx1+1, #balls do
			local b2 = balls[idx2]

			local dx, dy = b1.x - b2.x, b1.y - b2.y

			if dx == 0 and dy == 0 then
				-- Balls are on exactly the same spot, would get divide by zero
				b1.y -= 0.5
				b2.y += 0.5
				dy = b1.y - b2.y
			end

			local overlap, d = calc_overlap(dx, dy, BALL_D)

			if overlap > 0 then
				any_collisions = true

				local push = 0.5 * overlap

				b1.x += dx*push
				b1.y += dy*push
				b2.x -= dx*push
				b2.y -= dy*push

				local coll1 = {x=b2.x, y=b2.y}
				local coll2 = {x=b1.x, y=b1.y}

				-- If it's the current player, award bonus shots
				if (b1 == current_player.ball or b2 == current_player.ball) current_player.bonus_shots = current_player.bonus_shots or 2

				-- If no balls are moving, then we can skip this part entirely
				if moving_cooldown > 0 then

					local nx, ny = dy / d, -dx / d

					coll1.nx, coll1.ny = nx, ny
					coll2.nx, coll2.ny = nx, ny

					b1.vx *= VELOCITY_REDUCE_BALL_COLLISION
					b1.vy *= VELOCITY_REDUCE_BALL_COLLISION
					b2.vx *= VELOCITY_REDUCE_BALL_COLLISION
					b2.vy *= VELOCITY_REDUCE_BALL_COLLISION

					local dd1x, dd1y = dotpart(b1.vx, b1.vy, nx, ny)
					local dd2x, dd2y = dotpart(b2.vx, b2.vy, nx, ny)

					-- Play sound
					local dv = sqrt(dd1x*dd1x + dd1y*dd1y + dd2x*dd2x + dd2y*dd2y)
					sfx(min(round(4 * dv + 7), 10))
					debug_last_dv = dv

					b1.vx += -dd1x + dd2x
					b1.vy += -dd1y + dd2y
					b2.vx += -dd2x + dd1x
					b2.vy += -dd2y + dd1y
				end

				add(b1.collisions, coll1)
				add(b2.collisions, coll2)
			end
		end
	end

	return any_collisions
end

function check_wicket_collision(ball, w, dx, dy)

	local overlap, d = calc_overlap(dx, dy, BALL_POLE_D)

	if (overlap <= 0) return false

	local coll = {x=w.x, y=w.y}

	ball.x += dx*overlap
	ball.y += dy*overlap

	if moving_cooldown > 0 then
		-- Play sound
		if w.pole then
			sfx(4)
			sfx(5)
		else
			sfx(6)
		end

		local nx, ny = dx / d, dy / d
		coll.nx, coll.ny = nx, ny

		assert(
			-1.01 < nx and nx < 1.01 and -1.01 < ny and ny < 1.01,
			'dx=' .. dx ..
			',dy=' .. dy ..
			',d=' .. d ..
			',nx=' .. nx ..
			',ny=' .. ny
		)

		local vel_reduce = VELOCITY_REDUCE_WICKET_COLLISION
		if (w.pole) vel_reduce = VELOCITY_REDUCE_POLE_COLLISION

		coll.vx_before, coll.vy_before = ball.vx, ball.vy

		ball.vx *= vel_reduce
		ball.vy *= vel_reduce

		local vx, vy = ball.vx, ball.vy
		local v_dot_n = vx * nx + vy * ny

		ball.vx -= 2 * v_dot_n * nx
		ball.vy -= 2 * v_dot_n * ny

		coll.vx_after, coll.vy_after = ball.vx, ball.vy
	end

	add(ball.collisions, coll)

	return true
end

function wicket_collisions()

	local any_collisions = false

	for player in all(players) do
		local ball = player.ball
		if ball then
			for w in all(WICKET_COLLISION_POINTS) do

				local dx, dy, d2 = ball.x - w.x, ball.y - w.y

				if dx == 0 and dy == 0 then
					-- Ball is on exactly the same spot, would get divide by zero
					ball.y += 1
					dy = ball.y - w.y
				end

				d2 = distance_squared(dx, dy)

				if d2 <= BALL_POLE_D2 then
					if not w.hidden then
						if (check_wicket_collision(ball, w, dx, dy)) any_collisions = true
					end

					if w.pole and w.idx == player.last_wicket_idx + 1 then
						score_wicket(player)
						-- This could have triggered end of game
						if (player.finish_position) return
					end
				end
			end
		end
	end

	return any_collisions
end

function collisions()
	-- Returns true if any collisions occurred
	local any_collisions = wicket_collisions()
	return ball_collisions() or any_collisions
end

function any_collisions_for_ball(ball)
	for w in all(WICKET_COLLISION_POINTS) do
		if (distance_squared(ball.x - w.x, ball.y - w.y) <= BALL_POLE_D2) return true
	end
	for b in all(balls) do
		if b != ball then
			if (distance_squared(ball.x - b.x, ball.y - b.y) <= BALL_D2) return true
		end
	end
	return false
end

function resolve_all_static_collisions_for_ball(ball)

	local x_orig, y_orig, stuck_counter = ball.x, ball.y, 0

	for i = 1,200 do
		local any_collisions = wicket_collisions()

		-- This logic needs to be slightly different from regular ball collisions
		-- On collision, we only move this ball, not the other
		-- TODO: consolidate?
		for b2 in all(balls) do
			assert(b2)
			if b2 != ball then

				local dx, dy = ball.x - b2.x, ball.y - b2.y

				if dx == 0 and dy == 0 then
					-- Balls are on exactly the same spot, would get divide by zero
					ball.y += 1
					dy = ball.y - b2.y
				end

				local overlap, d = calc_overlap(dx, dy, BALL_D)

				if overlap > 0 then
					any_collisions = true
					add(ball.collisions, {x=b2.x, y=b2.y})
					add(b2.collisions, {x=ball.x, y=ball.y})
					ball.x += dx*overlap
					ball.y += dy*overlap
				end
			end
		end

		if (not any_collisions) return

		if i % 10 == 0 then
			-- If hitting lots of iterations, might be stuck between other balls/objects
			-- Move ball a random distance away from original position, increasing each time
			stuck_counter += 1
			ball.x = x_orig + 2 * stuck_counter * (rnd() - 0.5)
			ball.y = y_orig + 2 * stuck_counter * (rnd() - 0.5)
		end
	end

	assert(false, "resolve_all_static_collisions_for_ball hit iteration limit")
end

--
-- Title screen
--

function update_title_screen()

	local player = players[player_idx]

	if btnp(0) then
		-- Left
		if player.cpu then
			player.cpu = false
		elseif player.enabled then
			player.enabled = false
		else
			player.enabled = true
			player.cpu = true
		end
	end
	if btnp(1) then
		-- Right
		if player.cpu then
			player.enabled = false
			player.cpu = false
		elseif player.enabled then
			player.cpu = true
		else
			player.enabled = true
		end
	end

	num_players = 0
	for p in all(players) do
		if (p.enabled) num_players += 1
	end

	if btnp(2) then
		-- Up
		player_idx -= 2
		player_idx %= 6
		player_idx += 1
	end
	if btnp(3) then
		-- Down
		player_idx %= 6
		player_idx += 1
	end

	if (num_players > 0) and btnp(4) then

		-- player_idx = ceil(rnd(#players)) would work - next_player() will skip to next valid
		-- but this would not be fair when not using all players
		local valid_player_idxs = {}
		for idx = 1,#players do
			if (players[idx].enabled) add(valid_player_idxs, idx)
		end
		player_idx = valid_player_idxs[ceil(rnd(#valid_player_idxs))]

		next_player()

		game_started = true
	end

	cpu_update = stat(1)
end

function draw_title_screen_bg()
	rectfill(0, 0, 127, 31, 12)
	fillp(0b0101101001011010)
	rectfill(0, 32, 127, 127, 0xD3)
	fillp()

	for y=33,127 do

		local w = 0.5 * (y - 32)
		local d = 1/w

		local stripe = ((128 * d + 1.5) % 2) >= 1
		if (y <= 48) stripe = (y % 2) < 1

		if stripe then
			for idx=-TITLE_SCREEN_STRIPES,TITLE_SCREEN_STRIPES do
				local x = 64 - 2*idx*w
				line(x - w, y, x - 1, y, 0xD)
			end
		else
			for idx=-TITLE_SCREEN_STRIPES,TITLE_SCREEN_STRIPES do
				local x = 64 - 2*idx*w
				line(x, y, x + w - 1, y, 0x3)
			end
		end
	end
end

function draw_title_screen()
	camera()
	draw_title_screen_bg()

	-- Text besides players

	print_centered('croqu-8', 64, 14, 7)

	if (num_players > 0) and (time() % 1.0) > 0.5 then
		print_centered('press 🅾️', 64, 100, 7)
	end

	-- Pole

	local x1, x2, y1 = 30, 34, 48

	rectfill(x1, y1, x2, 128, 4)
	line(x1, y1, x1, 128, 9)
	line(x2, y1, x2, 128, 2)
	rectfill(x1+1, y1-2, x2-1, y1, 10)
	pset(x1, y1-1, 10)
	pset(x2, y1-1, 10)

	pal()
	palt()
	spr(54, x1 - 1, 124, 2, 1)
	reset_palette()

	-- Stripes & player info

	for idx = 1,#players do
		local p = players[idx]

		local py1 = y1 + 7*idx
		local py2 = py1 + 5

		rectfill(x1 + 1, py1, x2 - 1, py2, p.color_main)
		line(x1, py1-1, x1, py2-1, p.color_light)
		line(x2, py1-1, x2, py2-1, p.color_dark)

		local col = p.color_main
		if (col == 11) col = 7

		if p.enabled then
			if p.cpu then
				print_centered('cpu', 64, py1, col)
			else
				print_centered('player', 64, py1, col)
			end
		else
			print_centered('off', 64, py1, 0)
		end

		if idx == player_idx then
			print('⬅️', 64 - 20 - 4, py1, 7)
			print('➡️', 64 + 20 - 4, py1, 7)
		end

	end

	if (DEBUG) print(round(stat(1) * 100), 116, 1, 8)

	pal(DISPLAY_PALETTE, 1)
end

function draw_game_finished()
	camera()

	poke(0x5f5f,0x10)
	pal(DISPLAY_PALETTE, 1)
	memset(0x5f70, 0xff, 4)

	draw_title_screen_bg()

	-- Make sky a sunset instead
	local p1 = 0b0010100001011010
	local p2 = 0b0101101001111111

	fillp(p1)
	rectfill(0, 0, 127, 3, 0xC1)
	fillp(p2)
	rectfill(0, 4, 127, 7, 0xC1)
	fillp(p1)
	rectfill(0, 8, 127, 11, 0xFC)
	fillp(p2)
	rectfill(0, 12, 127, 15, 0xFC)
	fillp(p1)
	rectfill(0, 16, 127, 19, 0xEF)
	fillp(p2)
	rectfill(0, 20, 127, 23, 0xEF)
	fillp(p1)
	rectfill(0, 24, 127, 27, 0x9E)
	fillp(p2)
	rectfill(0, 28, 127, 31, 0x9E)
	fillp()

	for p in all(players) do
		if (p.enabled) assert(p.finish_position)
	end

	local y = 40
	print_centered('turns', 88, y, 7)
	print_centered('shots', 112, y, 7)
	y += 8
	for i = 1,num_players do

		local player = nil
		for p in all(players) do
			if p.finish_position == i then
				player = p
				break
			end
		end
		assert(player)

		if i <= 3 then
			spr(48 + i, 38, y - 1)
		else
			print(i, 40, y, 7)
		end

		if player.cpu then
			print_centered('cpu', 64, y, player.color_main)
		else
			print_centered('player', 64, y, player.color_main)
		end

		print_centered(player.total_turns, 88, y, 7)
		print_centered(player.total_shots, 112, y, 7)

		y += 8
	end

	if (DEBUG) print(round(stat(1) * 100), 116, 1, 8)
end

--
-- CPU AI logic
--

function cpu_get_target()
	local player = players[player_idx]
	local player_ball, next_wicket = player.ball, WICKETS[player.last_wicket_idx + 1]

	local tx, ty = next_wicket[1], next_wicket[2]
	local dx, dy = tx - player_ball.x, ty - player_ball.y
	local d = distance(dx, dy)

	-- Determine a few flags that will be used later
	local easy_shot, wrong_side, target_angle_deg = cpu_check_next_wicket_flags(next_wicket, dx, dy, d)
	local nearest_ball_d = nearest_ball_distance(player_ball)
	local clear_shot = nearest_ball_d > AI_CLEAR_SHOT_MIN_BALL_DISTANCE_SQUARED
	local target_blocked = wicket_between(player_ball, tx, ty)

	-- With no other balls in the way, this CPU player is too good - it can win before another player has a chance
	-- But it does much worse when other balls are involved
	-- So add a bit of handicap when there are no other balls anywhere close
	-- Also add this slop when way ahead of everyone
	local slop = 0
	if (clear_shot) slop += 1

	local lead_point_gap = lead_point_gap()
	-- 3-4: 1 / 5-6: 2 / 7-8: 3 / 9+: 4
	if (lead_point_gap >= 3) slop += min(4, flr((lead_point_gap - 1) / 2))
	if (lead_point_gap <= -2) slop -= 1
	if (lead_point_gap <= -5) slop -= 1

	--[[
	First determine ideal target point, without accounting for other balls

	Target point might not be right under the wicket in some cases - might want to aim slightly in front

	TODO:
	- See if we're lined up in a way that can score 2 wickets at once (or even 2 wickets + pole) and go for that
	- See if we can hit a ball past the next wicket
	]]

	local target_distance_past, play_safe_chance = 0, nil

	if (easy_shot and not wrong_side) or next_wicket.pole then
		-- Easy shot, or targeting a pole; no point trying any of the play-safe logic
		target_distance_past = AI_TARGET_PAST_WICKET_POLE_DISTANCE

	elseif target_angle_deg >= 120 then
		-- Wrong side of wicket (by a lot), keep targeting center of wicket

	else
		-- Determine odds of playing it safe (targeting in
		-- front of wicket instead of trying to go through)

		if target_blocked or (player.bonus_shots or 0) >= 2 then
			-- If target blocked, always play safe
			-- Or if we have bonus shots we will lose on going through wicket, so no reason not to play this shot safe
			-- TODO: don't do this when there's a ball in the way of the next wicket - would rather target that ball,
			-- and targeting in front could make that not happen in some cases
			play_safe_chance = 1

		else
			-- 30: 0
			-- 75: 1
			local angle_factor = max(0, target_angle_deg - 30) / 45

			-- 32: 0
			-- 192: 1
			local distance_factor = max(0, d - 32) / 160

			play_safe_chance = angle_factor + distance_factor

			-- Slop factor - safer when shot will be less accurate
			local slop_factors = { 1, 1.125, 1.25, 1.5 }
			play_safe_chance *= slop_factors[clip_num(flr(slop) + 1, 1, 4)]

			-- Extra (non bonus) shots factor
			local shots_factors = {1, 1.5, 2}
			play_safe_chance *= shots_factors[clip_num(player.shots, 1, 3)]

			-- Factor in point gap - riskier when behind, safer when ahead
			if lead_point_gap >= 3 then
				--[[
				(+1: 1)
				(+2: 1.25)
				+3: 1.5
				+4: 1.75
				+5: 2.0
				]]
				play_safe_chance *= 0.75 + 0.25 * lead_point_gap
			elseif lead_point_gap < -2 then
				--[[
				(-1: 1)
				(-2: 7/8)
				-3: 0.75
				-4: 5/8
				-5: 0.5
				-6: 3/8
				-7: 0.25
				-8: 1/8
				-9: 0
				]]
				play_safe_chance *= max(0, lead_point_gap + 9) / 8
			end

			-- If this is our last shot and there are other balls near the target,
			-- play riskier since they might want to hit us
			local target_nearest_ball_d = nearest_ball_distance(player_ball, tx, ty)
			if player.shots + (player.bonus_shots or 0) <= 1 and target_nearest_ball_d <= 64 then
				--[[
				1: 1 - 4/8 = 1 - 1/2 = 1/2
				8: 1 - 4/8 = 1 - 1/2 = 1/2
				16: 1 - 4/16 = 1 - 1/4 = 3/4
				32: 1 - 4/32 = 1 - 1/8 = 7/8
				64: 1 - 4/64 = 1 - 1/16 = 15/16
				]]
				play_safe_chance *= 1 - 4 / max(8, target_nearest_ball_d)
			end
		end

		-- If play_safe_chance < 10% or > 90%, snap to 0 or 1
		if (play_safe_chance > 0.9) or (play_safe_chance >= 0.1 and play_safe_chance >= rnd()) then

			-- Target in front of wicket

			-- TODO: This logic can sometimes be bad, like when we just barely made it through the last wicket,
			-- it causes us to aim further in front of the next wicket, which is worse for the nearby wicket

			for i = 1,3 do

				local tx_was, target_blocked_was = tx, target_blocked

				if next_wicket.reverse then
					tx += AI_TARGET_AHEAD_OF_WICKET_DISTANCE
				else
					tx -= AI_TARGET_AHEAD_OF_WICKET_DISTANCE
				end

				-- Update target_blocked for new target
				target_blocked = wicket_between(player_ball, tx, ty)

				-- If target isn't blocked, then we're fine with this position
				if (not target_blocked) break

				-- If target became blocked from this, then stick with what it was before
				if not target_blocked_was then
					-- This would make the target become newly blocked, so don't do it
					tx, target_blocked = tx_was, target_blocked_was
					break
				end

				-- Otherwise, target was blocked before, and still is - try next step further...
			end

		else
			-- Targeting wicket directly
			-- Shift angle slightly away from center of wicket
			ty += cpu_shift_y_away_from_center_of_wicket(dy)
			target_distance_past = AI_TARGET_PAST_WICKET_POLE_DISTANCE
		end

	end

	local target_ball

	if target_blocked or not player.bonus_shots then
		-- No bonus shots, so target another ball to get them
		-- Or target is blocked

		target_ball = cpu_target_ball(player_ball, next_wicket, wrong_side, easy_shot, target_blocked)

		if target_ball then
			tx, ty = cpu_adjust_target_for_ball(tx, ty, target_ball)
		end
	end

	-- Check if there's a ball between here and whatever is the current target
	-- If so, target that ball instead

	local other_ball_margin = 2
	if (d <= 16) other_ball_margin = 0

	local target_ball_between = ball_between(player_ball, tx, ty, other_ball_margin)
	if target_ball_between then
		target_ball = target_ball_between
		tx, ty = cpu_adjust_target_for_ball(tx, ty, target_ball)
	end

	--
	-- Target slightly past chosen point
	--

	local tx_orig, ty_orig = tx, ty

	if (target_ball) target_distance_past = AI_TARGET_PAST_BALL_DISTANCE

	if target_distance_past > 0 then
		tx, ty = cpu_target_past(player_ball, tx, ty, target_distance_past)
	end

	--
	-- Determine angle & power to hit target
	--

	local target_power, target_angle = cpu_determine_target_power_angle(player_ball, tx, ty, target_ball)

	--
	-- Add slop
	--

	if (target_ball and lead_point_gap <= 0) slop -= 1

	target_power, target_angle = cpu_add_error(target_power, target_angle, max(slop, 0))

	target_angle = round(target_angle * 256) / 256
	target_power = clip_num(target_power, SHOT_POWER_METER_RATE, 1.0)

	return {
		angle=target_angle,
		power=target_power,
		-- Only power & angle are needed, the rest is for debugging
		x=tx,
		y=ty,
		d=d,
		x_orig=tx_orig,
		y_orig=ty_orig,
		slop=slop,
		target_angle_deg=target_angle_deg,
		easy_shot=easy_shot,
		wrong_side=wrong_side,
		target_blocked=target_blocked,
		clear_shot=clear_shot,
		targeting_ball=targeting_ball,
		lead_point_gap=lead_point_gap,
		play_safe_chance=play_safe_chance,
	}
end

function cpu_adjust_target_for_ball(tx, ty, target_ball)

	-- Don't target ball head-on - adjust angle a smidge toward previous tx/ty

	local tx_new, ty_new = target_ball.x, target_ball.y

	local dx, dy = tx - target_ball.x, ty - target_ball.y
	local d = distance(dx, dy)
	if d then
		local scale = 0.5 * BALL_R / d
		tx_new += dx * scale
		ty_new += dy * scale
	end

	return tx_new, ty_new
end

function cpu_check_next_wicket_flags(next_wicket, dx, dy, d)

	local easy_shot, wrong_side, target_angle_deg = false, false, 0

	if next_wicket.pole then
		easy_shot = d < 16

	else
		if (next_wicket.reverse) dx = -dx

		wrong_side = dx < 0

		target_angle_deg = abs(((360*atan2(dx, dy) + 180) % 360) - 180)

		easy_shot = (abs(dx) < 16 and target_angle_deg < 30) or (abs(dx) < 8 and abs(dy) < 4)
	end

	return easy_shot, wrong_side, target_angle_deg
end

function cpu_target_past(player_ball, tx, ty, extra_distance)
	local dx, dy = tx - player_ball.x, ty - player_ball.y
	local d = distance(dx, dy)
	tx += extra_distance * (dx / d)
	ty += extra_distance * (dy / d)
	return tx, ty
end

function cpu_shift_y_away_from_center_of_wicket(dy)

	if dy > 16 then
		return 2
	elseif dy < -16 then
		return -2
	elseif dy > 4 then
		return 1
	elseif dy < -4 then
		return -1
	end

	return 0
end

function nearest_ball_distance(ball, x, y)
	x, y = x or ball.x, y or ball.y
	local d2 = 32767
	for other_ball in all(balls) do
		if other_ball != ball then
			d2 = min(d2, distance_squared(ball.x - other_ball.x, ball.y - other_ball.y))
		end
	end
	return sqrt(d2)
end

function lead_point_gap()

	local max_other_player_wicket = 0

	for i = 1,#players do
		local p = players[i]
		if i != player_idx and p.enabled then
			max_other_player_wicket = max(max_other_player_wicket, p.last_wicket_idx)
		end
	end

	return players[player_idx].last_wicket_idx - max_other_player_wicket
end

function wicket_between(ball, tx, ty, target_is_ball, margin)

	local x1, y1, x2, y2 = ball.x, ball.y, tx, ty

	local line_dx, line_dy = x2 - x1, y2 - y1

	local d2 = distance_squared(line_dx, line_dy)
	assert(d2 >= 0)
	local d = sqrt(d2)

	-- In case of distance 0, just return that it's not between
	if (d == 0) return false

	-- We don't want to use center of ball, but rather outer edges of ball
	-- (e.g. in case our ball, or target ball, is straddling a wicket)
	-- So instead of checking if t is in range [0, 1] below, use slightly smaller range
	local t_min = BALL_R / d

	local t_max = 1
	if (target_is_ball) t_max = 1 - t_min

	if (t_min >= t_max or t_max <= 0 or t_min >= 1) return false

	for wicket in all(WICKET_COLLISION_POINTS) do
		-- Hidden wickets would be redundant
		-- TODO optimization: instead, maintain separate list of non-hidden wickets and just iterate that
		if not wicket.hidden then

			-- Determine distance from point (wicket.x, wicket.y) to line segment [(x1, y1), (x2, y2)]

			local wicket_dx = wicket.x - x1
			local wicket_dy = wicket.y - y1

			-- Project point onto the line

			-- First, determine interpolation parameter along line segment: t = 0 at (x1, y1), 1 at (y2, y2)
			local t = (wicket_dx * line_dx + wicket_dy * line_dy) / d2

			-- If t is not in range [0, 1] (or slightly less - see above), then projected point is beyond ends of line segment
			-- If it is, then project it onto line segment, and check distance from projected point
			if t_min < t and t < t_max then
				local proj_x = lerp(x1, x2, t)
				local proj_y = lerp(y1, y2, t)
				if (distance(wicket.x - proj_x, wicket.y - proj_y) < BALL_POLE_D + (margin or 0)) return true
			end
		end
	end

	return false
end

function ball_between(ball, tx, ty, margin)
	-- Checks if there are any balls between ball & target. If so, returns the ball that is closest to ball
	-- Largely copied from wicket_between(), but a few differences
	-- TODO: try to consolidate these functions?

	local bx, by = ball.x, ball.y

	local line_dx, line_dy = tx - bx, ty - by
	local d2 = distance_squared(line_dx, line_dy)
	assert(d2 >= 0)
	if (d2 == 0) return false

	-- Unlike wicket_between(), we leave t_max as 1 - if a ball is overlapping the target, then still want to target the ball
	local t_min = BALL_R / sqrt(d2)
	if (t_min >= 1) return false

	local closest_ball = nil
	local closest_ball_d2 = 32767

	for other_ball in all(balls) do
		if other_ball != ball then
			local ball_dx = other_ball.x - bx
			local ball_dy = other_ball.y - by

			local t = (ball_dx * line_dx + ball_dy * line_dy) / d2

			if t_min < t and t < 1 then
				local proj_x = lerp(bx, tx, t)
				local proj_y = lerp(by, ty, t)

				local ball_distance = distance(other_ball.x - proj_x, other_ball.y - proj_y)
				if (ball_distance <= BALL_D + (margin or 0)) then
					local other_ball_d2 = distance_squared(ball_dx, ball_dy)
					if (other_ball_d2 < closest_ball_d2) closest_ball, closest_ball_d2 = other_ball, other_ball_d2
				end
			end
		end
	end

	return closest_ball
end

function cpu_target_ball(player_ball, next_wicket, wrong_side, easy_shot, target_blocked)

	local tx, ty = next_wicket[1], next_wicket[2]
	local d = distance(tx - player_ball.x, ty - player_ball.y)

	-- Only target a ball if the weighted distance is less than this
	local best_score = 0.75 * d
	if (next_wicket.pole) best_score = 0.5 * d

	if wrong_side or target_blocked then
		-- In one of these cases, always go for closest ball (within a reasonable range)
		best_score = AI_TARGET_BALL_MAX_WEIGHTED_DISTANCE
	elseif easy_shot then
		-- May still want to target another ball just to move it - but only if it's not far out of the way
		best_score = min(best_score, AI_TARGET_BALL_MAX_WEIGHTED_DISTANCE_EASY_SHOT)
	end
	best_score = min(best_score, AI_TARGET_BALL_MAX_WEIGHTED_DISTANCE)

	-- Figure out best ball to target for bonus shot
	local target_ball
	for b in all(balls) do
		if b != player_ball and not wicket_between(player_ball, b.x, b.y, true, 1.5) then

			local d_self = distance(b.x - player_ball.x, b.y - player_ball.y)

			local dx_target = b.x - tx
			local d_target = distance(dx_target, b.y - ty)

			local score = 0.75 * d_self + 0.25 * d_target

			-- Penalize if other ball is on wrong side of target (unless we're also on wrong side)
			if not (next_wicket.pole or wrong_side) then
				if ((not next_wicket.reverse) and dx_target > 2) score *= 2
				if (next_wicket.reverse and dx_target < -2) score *= 2
			end

			if score < best_score then
				-- This is the best candidate so far
				target_ball, best_score = b, score
			end
		end
	end

	return target_ball
end

function cpu_determine_target_power_angle(player_ball, tx, ty, target_ball)

	dx, dy = tx - player_ball.x, ty - player_ball.y
	local target_angle = atan2(dx, dy)

	local d = distance(dx, dy)

	local target_power = sqrt(d) / 14

	-- If we're targeting a nearby ball, increase power
	-- Note that "cpu_target_past" has already been handled, so don't need to add extra for that
	if target_ball then
		if (d < 32) target_power *= 1.5
		if (d < 16) target_power *= 1.333333333
	end

	return clip_num(target_power, SHOT_POWER_METER_RATE, 1-SHOT_POWER_METER_RATE), target_angle
end

function cpu_add_error(target_power, target_angle, slop)

	-- TODO: multiply r by slop (might need to rebalance the other values too)
	local r = rnd() - 0.5
	local angle_err = ANGLE_STEP
	if abs(r) > 0.4 then
		angle_err *= 2
	elseif abs(r) < 0.25 then
		angle_err = 0
	end
	target_angle = (target_angle + slop * sgn(r) * angle_err) % 1.0

	target_power += slop * (rnd() - 0.5) / 32

	return target_power, target_angle
end

--
-- Game logic
--

function reset_off_screen_balls()
	for ball in all(balls) do
		local x_was, y_was = ball.x, ball.y
		ball.x = clip_num(ball.x, ROUGH, WIDTH-ROUGH-1)
		ball.y = clip_num(ball.y, ROUGH, HEIGHT-ROUGH-1)
		if (ball.x != x_was or ball.y != y_was) resolve_all_static_collisions_for_ball(ball)
	end
end

function next_shot_same_player()
	reset_off_screen_balls()
	local player = players[player_idx]
	shot_power, shot_angle, shot_power_change, camera_look_ahead, player.cpu_target = 0, 0, 0, true, nil
	if (WICKETS[player.last_wicket_idx + 1][1] < player.ball.x) shot_angle = 0.5
end

function next_player()

	local player = players[player_idx]
	player.shots = 0
	if (player.bonus_shots) player.bonus_shots = 0

	player.cpu_target = nil

	local n_iter = 0
	while true do
		player_idx %= #players
		player_idx += 1
		player = players[player_idx]

		if (player.enabled and not player.finish_position) break

		n_iter += 1
		assert(n_iter <= #players)
	end

	if (not player.ball) reset_ball(player)

	next_shot_same_player()

	assert(player.shots == 0, 'player.shots='..player.shots)
	assert((not player.bonus_shots) or (player.bonus_shots == 0), 'player.bonus_shots='..(player.bonus_shots or 'nil'))
	player.shots = 1
	player.total_turns += 1

	update_camera()
end

function score_wicket(player)
	player.last_wicket_idx += 1

	-- At this point the camera must have caught up to the wicket, so stop looking ahead
	camera_look_ahead = false

	if player.last_wicket_idx < #WICKETS then
		-- Not the last wicket
		-- TODO: play a sound
		if (player == players[player_idx]) player.shots += 1
		player.bonus_shots = nil

	else
		-- Last wicket; finish the game for this player
		-- TODO: play a sound
		num_players_finished += 1
		player.finish_position, player.shots, player.bonus_shots, player.ball = num_players_finished, 0, nil, nil
		balls = {}
		for p in all(players) do
			if (p.ball) add(balls, p.ball)
		end
	
		if num_players_finished >= num_players then
			game_finished = true
		end
	end
end

function reset_ball(player)
	local palette = player.palette

	assert(not player.finish_position)

	player.selected_starting_point = false

	local y = WICKETS[1][2] + 4
	if (player.cpu) y = WICKETS[1][2] - 4

	local ball = {
		x=WICKETS[1][1],
		y=y,
		vx=0,
		vy=0,
		color=palette[8],
		palette=palette,
		collisions={},
	}
	player.ball = ball

	balls = {}
	for p in all(players) do
		if (p.ball) add(balls, p.ball)
	end

	local dy = 1
	while any_collisions_for_ball(ball) do
		ball.y += dy
	end
end

function add_wicket_collision_points(idx, wicket)
	if wicket.pole then
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] - 1, idx=idx, pole=true, hidden=wicket.hidden })
	else
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] - 5, idx=idx, hidden=wicket.hidden })
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] + 4, idx=idx, hidden=wicket.hidden })
	end
end

function _init()
	players, balls, WICKET_COLLISION_POINTS = {}, {}, {}

	-- Add hidden wickets first
	for idx = 1,#WICKETS do
		local wicket = WICKETS[idx]
		if (wicket.hidden) add_wicket_collision_points(idx, wicket)
	end
	for idx = 1,#WICKETS do
		local wicket = WICKETS[idx]
		if (not wicket.hidden) add_wicket_collision_points(idx, wicket)
	end

	for idx = 1,#PALETTES do
		local palette = PALETTES[idx]
		add(players, {
			enabled=idx <= 4, -- Default to 4 players
			cpu=idx > 1, -- Default to 1 human player
			palette=palette,
			color_main=palette[8],
			color_light=palette[14],
			color_dark=palette[2],
			ball=nil,
			selected_starting_point=false,
			last_wicket_idx=1,
			shots=0,
			bonus_shots=nil,
			total_shots=0,
			total_turns=0,
			cpu_target=nil,
			finish_position=nil,
		})
	end

	cls()
	if (DEBUG) poke(0x5F2D, 1)  -- enable keyboard
	poke(0x5f36, 0x40)  -- prevent printing at bottom of screen from triggering scroll
end

function check_wickets(player)
	-- Note: only checks wickets, not poles
	-- (Poles are handled through collision physics)

	local ball, w = player.ball, WICKETS[player.last_wicket_idx + 1]
	if ((not w) or w.pole or not ball) return

	assert(not player.finish_position)

	local x, y, xp, yp, wx, wy = ball.x, ball.y, ball.x_prev, ball.y_prev, w[1], w[2]

	local through = false
	if wy - 5 <= y and y <= wy + 4 then
		if x == wx then
			-- In case ball is stopped exactly on wicket
			-- (Could handle this with conditions below, but this is more mistake-proof)
			-- FIXME: technically this could trigger a wicket when going the wrong direction
			through = true
		elseif w.reverse then
			if (xp >= wx and x < wx) through = true
		else
			if (xp <= wx and x > wx) through = true
		end
	end
	if (through) score_wicket(player)
	assert(not player.finish_position) -- should only finish on a pole
end

function launch_ball()

	local angle_rand = rnd() - 0.5
	-- Range is [0.5, 0.5)
	if (abs(angle_rand) < 0.25) angle_rand *= 2
	-- Range is still [0.5, 0.5), but biased away from center

	if shot_power_over then
		-- Add extra error
		angle_rand *= 2 * SHOT_POWER_ERR_OVER
	else
		-- Add a little bit of randomness to hard shots
		angle_rand *= SHOT_POWER_ERR_MAX_POWER * max(0, 2 * (shot_power - 0.5))
	end

	shot_angle += angle_rand
	shot_angle = round((shot_angle * 256) % 256) / 256

	local player = players[player_idx]
	local dx, dy = cos(shot_angle), sin(shot_angle)
	local v = SHOT_V_MIN + (SHOT_V_MAX - SHOT_V_MIN) * shot_power * shot_power

	player.ball.vx = v * dx
	player.ball.vy = v * dy
	moving_cooldown = MOVING_COOLDOWN_FRAMES

	if player.bonus_shots and player.bonus_shots > 0 then
		player.bonus_shots -= 1
	else
		player.shots -= 1
	end

	player.total_shots += 1

	-- Play sound
	sfx(clip_num(flr(shot_power * 4), 0, 3))
	sfx(clip_num(7 + flr(shot_power * 4), 7, 10))
end

function _update60()

	if (game_finished) return

	local player = players[player_idx]
	local player_ball, op, x = player.ball, btnp(4), btn(5)
	local left, right, up, down = btn(0), btn(1), btn(2), btn(3)

	if DEBUG then
		while stat(30) do
			local key = stat(31)
			if (key == '1') debug_draw_primitives = not debug_draw_primitives
			if (key == '2') debug_increase_shot_pointer_length = not debug_increase_shot_pointer_length
			if (key == '3') debug_no_draw_tops = not debug_no_draw_tops
			if (key == '=') debug_pause_physics = not debug_pause_physics

			if game_started and moving_cooldown <= 0 then

				if (key == '7') player.bonus_shots = nil
				if (key == '8') player.bonus_shots = 0
				if (key == '9') player.bonus_shots = 1
				if (key == '0') player.bonus_shots = 2

				if key == ']' then
					next_player()
					player = players[player_idx]
					player_ball = player.ball
				end

				local moved = false

				if key == 'h' then
					player_ball.x -= 1
					moved = true
				elseif key == 'j' then
					player_ball.y += 1
					moved = true
				elseif key == 'k' then
					player_ball.y -= 1
					moved = true
				elseif key == 'l' then
					player_ball.x += 1
					moved = true
				end

				if moved then
					resolve_all_static_collisions_for_ball(player_ball)
					if (player.cpu) cpu_get_target()
				end
			end
		end
	end

	if not game_started then
		update_title_screen()

	elseif not player.selected_starting_point then
		update_select_starting_point()

	else
		-- TODO: refactor into function

		if player.cpu then
			-- CPU logic

			op, x, left, right, up, down = false, false, false, false, false, false

			if moving_cooldown <= 0 and not debug_pause_physics then		

				if (not player.cpu_target) player.cpu_target = cpu_get_target()

				if shot_power_change == 0 then
					local angle_err = ((shot_angle - player.cpu_target.angle + 0.5) % 1.0) - 0.5
					if angle_err >= ANGLE_STEP then
						right = true
					elseif angle_err <= -ANGLE_STEP then
						left = true
					else
						op = true  -- Start shot
					end
				elseif shot_power >= min(1, player.cpu_target.power) then
					op = true  -- Finish shot
				end
			end
		end

		if moving_cooldown <= 0 then

			if op then
				if shot_power_change > 0 then
					-- Shot power meter rising
					launch_ball()
					shot_power_change = 0
				elseif shot_power_change < 0 then
					-- Shot power meter falling
					launch_ball()
					shot_power_change = 0
				else
					-- Shot power = 0, start shot power meter
					shot_power_change = SHOT_POWER_METER_RATE
				end

				if shot_power_change == 0 then
					-- Re-enable key repeat
					poke(0x5f5c, 0)
					poke(0x5f5d, 0)
				else
					-- Disable key repeat
					poke(0x5f5c, 255)
					poke(0x5f5d, 255)
				end
			end

			shot_power += shot_power_change

			if shot_power >= 1 then
				shot_power_change = SHOT_POWER_METER_FALL_RATE
				shot_power_over = true
			elseif shot_power <= 0 then
				shot_power_change = 0
				shot_power_over = false
			end

			shot_power = clip_num(shot_power, 0, 1)
		end

		for ball in all(balls) do
			ball.collisions = {}
		end

		if moving_cooldown > 0 then

			if (not debug_pause_physics) or op then

				-- Process physics

				moving_cooldown -= 1

				-- TODO optimization: keep a list of moving players, only iterate those
				-- TODO optimization: when looping through each ball, make a list of close players & wickets
				-- (with simpler check, e.g. abs(dx)+abs(dy)), then these are the only ones that get checked for collisions

				for ball in all(balls) do
					ball.x_prev = ball.x
					ball.y_prev = ball.y
				end

				for idx=1,COLLISION_CHECK_DIVISIONS do
					for ball in all(balls) do
						if ball.vx != 0 or ball.vy != 0 then
							ball.x += ball.vx / COLLISION_CHECK_DIVISIONS
							ball.y += ball.vy / COLLISION_CHECK_DIVISIONS
						end
					end
					if (collisions()) moving_cooldown = MOVING_COOLDOWN_FRAMES
				end

				for ball in all(balls) do
					if ball.vx != 0 or ball.vy != 0 then

						local drag = DRAG
						if (ball.x < ROUGH or ball.y < ROUGH or ball.x >= WIDTH-ROUGH or ball.y >= HEIGHT-ROUGH) drag = DRAG_ROUGH

						ball.vx *= drag
						ball.vy *= drag

						local v2 = ball.vx*ball.vx + ball.vy*ball.vy
						if (v2 <= V2_STOP_THRESH) then
							-- Stop ball
							ball.vx, ball.vy = 0, 0

							-- Move ball slightly when it stops
							-- TODO: Add ball spin, and make this depend on it
							if not any_collisions_for_ball(ball) then
								local x1, y1 = ball.x, ball.y
								ball.x = round(ball.x + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
								ball.y = round(ball.y + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
								local x2, y2 = ball.x, ball.y
								resolve_all_static_collisions_for_ball(ball)
								-- If static collisions caused significant movement, forget about the stop movement entirely
								if distance_squared(ball.x - x2, ball.y - y1) > 1 then
									ball.x, ball.y = x1, y1
								end
							end
						end
						moving_cooldown = MOVING_COOLDOWN_FRAMES
					end
				end
			end

			for player in all(players) do
				check_wickets(player)
			end

			if moving_cooldown <= 0 then
				if player.finish_position then
					next_player()
				elseif (player.shots + (player.bonus_shots or 0)) <= 0 then
					next_player()
				else
					next_shot_same_player()
				end
			end
			-- Note: player could have changed due to next_player(), so player_ball will be stale - but we're not using it again

			update_camera()

		else
			if x then
				if (left)  camera_x -= 4
				if (right) camera_x += 4
				if (up)    camera_y -= 4
				if (down)  camera_y += 4
			else
				update_camera()
				if shot_power_change == 0 then
					if (left)  shot_angle += ANGLE_STEP
					if (right) shot_angle -= ANGLE_STEP
				end
			end

			shot_angle = round((shot_angle * 256) % 256) / 256
		end
	end

	moving_cooldown = max(moving_cooldown, 0)
	camera_x = clip_num(camera_x, 64 - STATUS_BAR_WIDTH, WIDTH-64)
	camera_y = clip_num(camera_y, 64, HEIGHT-64)

	cpu_update = stat(1)
end

function update_select_starting_point()
	local player = players[player_idx]
	local player_ball = player.ball, btnp(4)
	local left, right, up, down

	assert(player_ball)

	if player.cpu then
		player.selected_starting_point = true
		camera_x, camera_y = player_ball.x, player_ball.y

	elseif btn(5) then
		-- X
		-- TODO: consolidate this with the logic in _update60()
		local left, right, up, down = btn(0), btn(1), btn(2), btn(3)
		if (left)  camera_x -= 4
		if (right) camera_x += 4
		if (up)    camera_y -= 4
		if (down)  camera_y += 4
	else
		local up, down, o = btnp(2), btnp(3), btnp(4)

		local dy = 0
		if (up)    dy -= 1
		if (down)  dy += 1

		if dy != 0 then
			player_ball.y += dy
			while any_collisions_for_ball(player_ball) do
				player_ball.y += dy
			end
			-- Don't allow moving it offscreen
			reset_off_screen_balls()
		end

		-- O
		if (o) player.selected_starting_point = true

		update_camera()
	end
end

function draw_shot()
	local player = players[player_idx]
	assert(player.ball)
	local x, y = player.ball.x, player.ball.y
	if (not x) return -- HACK: this shouldn't be needed
	local dx, dy = cos(shot_angle), sin(shot_angle)

	-- Draw line

	local l = 24
	if (debug_increase_shot_pointer_length) l = 256

	line_round(x, y, x + l*dx, y + l*dy, shot_power_color())
end

function draw_club()

	local player = players[player_idx]
	assert(player.ball)
	local x, y = player.ball.x, player.ball.y
	if (not x) return -- HACK: this shouldn't be needed
	local dx, dy = cos(shot_angle), sin(shot_angle)
	local w, l, d = 1.5, 10, 4 + 5*shot_power

	-- Determine corners
	local c = {
		{ w*dy - d*dx,     -w*dx - d*dy},
		{ w*dy - (d+l)*dx, -w*dx - (d+l)*dy},
		{-w*dy - (d+l)*dx,  w*dx - (d+l)*dy},
		{-w*dy - d*dx,      w*dx - d*dy},
	}
	for i=1,4 do
		c[i][1] = round(x + c[i][1])
		c[i][2] = round(y + c[i][2])
	end

	if (dy > 0) c = { c[3], c[4], c[1], c[2] }

	-- Fill
	pelogen_tri_low(c[1][1], c[1][2], c[2][1], c[2][2], c[3][1], c[3][2], 4)
	pelogen_tri_low(c[3][1], c[3][2], c[4][1], c[4][2], c[1][1], c[1][2], 4)

	-- Sides - (pelogen_tri_low seems to have different rounding behavior, so these aren't necessarily covered)
	local col2 = 4
	if (abs(dy) >= 0.25) col2 = 2
	line(c[1][1], c[1][2], c[2][1], c[2][2], 4)
	line(c[3][1], c[3][2], c[4][1], c[4][2], col2)

	-- Ends
	line_round(c[1][1], c[1][2], c[4][1], c[4][2], 5)
	line_round(c[2][1], c[2][2], c[3][1], c[3][2], 5)

	-- Stripes in player color
	for i in all({1, 4}) do
		local x1, y1 = lerp_round(c[1][1], c[2][1], i/5), lerp_round(c[1][2], c[2][2], i/5)
		local x2, y2 = lerp_round(c[4][1], c[3][1], i/5), lerp_round(c[4][2], c[3][2], i/5)
		line(x1, y1, x2, y2, player.color_main)
		if abs(dy) >= 0.25 then
			pset(x1, y1, player.color_light)
			pset(x2, y2, player.color_dark)
		end
	end
end

function draw_status_bar()

	rectfill(1, 1, STATUS_BAR_WIDTH - 1, 128, 4)
	line(STATUS_BAR_WIDTH, 1, STATUS_BAR_WIDTH, 128, 2)
	line(0, 1, 0, 128, 9)
	line(0, 0, STATUS_BAR_WIDTH, 0, 9)
	pset(0, 0, 10)
	pset(STATUS_BAR_WIDTH, 0, 4)

	for idx = 1,#players do
		local p = players[idx]

		local main_color, textcol = p.color_main, 7
		if (p.color_main >= 9) textcol = 0

		local y1 = 9*idx-1
		local y2 = y1 + 6

		rectfill(1, y1, STATUS_BAR_WIDTH-1, y2, main_color)
		line(0, y1, 0, y2, p.color_light)
		line(STATUS_BAR_WIDTH, y1, STATUS_BAR_WIDTH, y2, p.color_dark)

		if (p.enabled) print_centered(p.last_wicket_idx - 1, 5, y1+1, textcol)

		local x = STATUS_BAR_WIDTH + 4

		if p.finish_position then
			if p.finish_position <= 3 then
				spr(48 + p.finish_position, x - 2, y1)
			else
				circfill(x + 1, y1 + 3, 3, 0)
				print(p.finish_position, x, y1 + 1, 7)
			end

		elseif idx == player_idx then
			pal(p.ball.palette)
			for i = 1,p.shots do
				spr(30, x-3, y1)
				x += 6
			end
			reset_palette()

			if p.bonus_shots then
				for i=1,2 do
					if (i <= p.bonus_shots) then
						pal(p.ball.palette)
						spr(7, x-3, y1)
						reset_palette()
						circ(x, y1 + 3, 2, textcol)
					else
						circ(x, y1 + 3, 2, textcol)
					end
					x += 6
				end
			end
		end
	end

	if shot_power > 0 or shot_power_change != 0 then
		-- Shot power meter
		local col = shot_power_color()
		local y = 125 - 60*shot_power
		rectfill(3, y, 5, 127, col)
		rect(2, 64, 6, 128, 0)
		print('◀', STATUS_BAR_WIDTH - 1, y-2, col)
	end

	if not debug_draw_primitives then
		palt()
		spr(54, 0, 124, 2, 1)
		reset_palette()
	end
end

function _draw()

	reset_palette()

	if game_finished then
		draw_game_finished()
		return
	elseif not game_started then
		draw_title_screen()
		return
	end

	local player, sprites, x, y = players[player_idx], {}
	local player_ball = players[player_idx].ball
	local next_wicket = WICKETS[player.last_wicket_idx + 1]

	camera(round(camera_x - 64), round(camera_y - 64))

	--
	-- Field
	--

	for y=0,ceil((HEIGHT-2*ROUGH)/16) do
		for x=0,ceil((WIDTH-2*ROUGH)/16) do
			local fp = 0b0101101001011010
			if (x % 2 == 0 and y % 2 == 0) fp = 0x0000
			if (x % 2 == 1 and y % 2 == 1) fp = 0xFFFF
			fillp(fp)
			local off = ROUGH
			if (ROUGH < 1) off = -8
			rectfill(x*16 + off, y*16 + off, x*16 + 16 + off, y*16 + 16 + off, 0xD3)
		end
	end
	if ROUGH > 0 then
		fillp(ROUGH_FILLP)
		rectfill(0, 0, WIDTH, ROUGH-1, ROUGH_COLOR)
		rectfill(0, HEIGHT - ROUGH, WIDTH, HEIGHT, ROUGH_COLOR)
		rectfill(0, ROUGH, ROUGH, HEIGHT - ROUGH, ROUGH_COLOR)
		rectfill(WIDTH - ROUGH, ROUGH, WIDTH, HEIGHT - ROUGH, ROUGH_COLOR)
	end
	fillp()

	-- Boundary
	if (ROUGH < 1) rect(0, 0, WIDTH - 1, HEIGHT - 1, 7)

	--
	-- Bases & shadows
	--

	-- Draw ball shadows
	if not debug_draw_primitives then
		for ball in all(balls) do
			spr(2, round(ball.x) - 2, round(ball.y) - 4)
		end
	end

	-- Draw wicket & pole bases
	if not debug_draw_primitives then
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					spr(39, w[1], w[2]-7)
				else
					spr(17, w[1]-1, w[2]-8, 1, 2)
				end
			end
		end
	end	

	-- Draw arrow on next wicket

	if next_wicket then
		x, y = next_wicket[1], next_wicket[2] - 3
		if next_wicket.pole then
			x -= 9
			if (next_wicket.reverse) x += 11
		elseif next_wicket.reverse then
			x -= 2
		end
		spr(3, x, y, 1, 1, next_wicket.reverse)
	end

	--
	-- Starting point area
	--

	if not player.selected_starting_point then
		local x, y = player_ball.x - 3, player_ball.y - 3
		spr(5, x, y - 12)
		spr(5, x, y + 12, 1, 1, false, true)
	elseif moving_cooldown <= 0 then
		draw_shot()
	end

	--
	-- Balls & wickets - stuff where Z-order matters
	--

	for ball in all(balls) do
		x, y = round(ball.x), round(ball.y)
		if debug_draw_primitives then
			circ(x, y, BALL_R, ball.color)
			pset(x, y, 0)
		else
			local idx = 8 + (round(0.5 * x) % 8) + 16*(round(0.5 * y) % 4)
			if (not player.selected_starting_point) idx = 30
			-- idx = 1 -- DEBUG
			add(sprites, {idx=idx, x=x - 3, y=y-3, z=y, pal=ball.palette})
		end
	end
	reset_palette()

	if (not debug_no_draw_tops) and (not debug_draw_primitives) then
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					add(sprites, {idx=23, x=w[1], y=w[2]-7, z=w[2]})
				else
					add(sprites, {idx=18, x=w[1]-1, y=w[2]-8, z=w[2]-4})
					add(sprites, {idx=34, x=w[1]-1, y=w[2], z=w[2]+4})
					add(sprites, {idx=19, x=w[1]-1, y=w[2]-8, z=w[2]+20}) -- Extra sprite for top
				end
			end
		end
	end

	--
	-- Draw sprites, in Z order
	--

	--[[
	TODO optimizations: (Bubblesort is slow, O(n^2))
	- Do not add offscreen sprites to list
	- Sort list of wickets at init, then they're already sorted
	- Sort list each time we add a sprite
	]]

	sort_z(sprites)

	for s in all(sprites) do
		if (s.pal) pal(s.pal)
		spr(s.idx, round(s.x), round(s.y), s.w or 1, s.h or 1)
		if (s.pal) reset_palette()
	end

	if DEBUG and player.cpu_target then
		line(
			player.cpu_target.x_orig - 2, player.cpu_target.y_orig,
			player.cpu_target.x_orig + 2, player.cpu_target.y_orig,
			9)
		line(
			player.cpu_target.x_orig, player.cpu_target.y_orig - 2,
			player.cpu_target.x_orig, player.cpu_target.y_orig + 2,
			9)

		line(
			player.cpu_target.x - 2, player.cpu_target.y,
			player.cpu_target.x + 2, player.cpu_target.y,
			14)
		line(
			player.cpu_target.x, player.cpu_target.y - 2,
			player.cpu_target.x, player.cpu_target.y + 2,
			14)
	end

	if debug_draw_primitives then

		-- Velocity
		for ball in all(balls) do
			line_round(
				ball.x,
				ball.y,
				ball.x + 30*ball.vx,
				ball.y + 30*ball.vy,
				11)
		end

		-- Current collisions
		for ball in all(balls) do
			for coll in all(ball.collisions) do

				-- Normal: orange
				if (coll.nx) line_round(ball.x, ball.y, ball.x + 16*coll.nx, ball.y + 16*coll.ny, 9)

				-- v before: blue
				if (coll.vx_before) line_round(ball.x, ball.y, ball.x - 30 * coll.vx_before, ball.y - 30*coll.vy_before, 12)

				-- v after: red
				if (coll.vx_after) line_round(ball.x, ball.y, ball.x + 30 * coll.vx_after, ball.y + 30*coll.vy_after, 8)

				line_round(ball.x, ball.y, coll.x, coll.y, 14)
			end
		end

		-- Wicket collision points
		for w in all(WICKET_COLLISION_POINTS) do
			local col = 9
			if (w.pole) col = 8
			if (w.hidden) col = 6
			pset(w.x, w.y, col)
		end
	end

	--
	-- Club
	--

	if (player.selected_starting_point and moving_cooldown <= 0) draw_club()

	--
	-- HUD
	--

	camera()
	draw_status_bar()

	--
	-- Debug overlays
	--

	if DEBUG then

		if debug_pause_physics then
			print_centered('paused', 64, 0, 8)
		end

		cursor(96, 1, 8)

		-- print('mem:' .. stat(0))
		local cpu = stat(1)
		-- local cpu_draw = cpu - cpu_update
		-- print('cpu:' .. round(cpu * 100) .. '=' .. round(cpu_update * 100) .. '+' .. round(cpu_draw * 100))
		print(round(cpu * 100))

		if not player.finish_position then

			print('x=' .. player_ball.x)
			print('y=' .. player_ball.y)
			print('m=' .. moving_cooldown)
			if (moving_cooldown <= 0) then
				print('p=' .. shot_power)
				print('a=' .. shot_angle*256)
			else
				print('vx=' .. player_ball.vx)
				print('vy=' .. player_ball.vy)
			end

			if (debug_last_dv) print('dv2=' .. debug_last_dv)

			if player.cpu_target then
				print('')
				print('tx=' .. player.cpu_target.x)
				print('ty=' .. player.cpu_target.y)
				print('td=' .. player.cpu_target.d)
				print('tp=' .. player.cpu_target.power)
				print('ta=' .. (player.cpu_target.angle * 360))
				print('deg=' .. player.cpu_target.target_angle_deg)
				print('saf=' .. (player.cpu_target.play_safe_chance or 'nil'))

				if (player.cpu_target.easy_shot) print('easy_shot')
				if (player.cpu_target.target_blocked) print('target_blocked')
				if (player.cpu_target.wrong_side) print('wrong_side')
				if (player.cpu_target.clear_shot) print('clear_shot')
				if (player.cpu_target.targeting_ball) print('targeting_ball')

				print('gap=' .. player.cpu_target.lead_point_gap)
				print('slop=' .. player.cpu_target.slop)
			end
		end
	end

	--
	-- Set display palette
	--

	pal(DISPLAY_PALETTE, 1)
end

__gfx__
00000000333333333333333333333333333333333333333300000000333333333333333333333333333333333333333333333333333333333333333333333333
0000000033e8833333333333333338333333033333303333000000003300033333e6833333ee833333ee833333ee833333e6833333ee833333ee833333ee8333
000000003e7e8833333333333333388333330033330003330000000030e880333e8788333e8878333e8888333e7888333e8788333e8878333e8888333e788833
0000000038e888333355553388888888300000033000003300000000308870333887883338878833367776333887883338878833388788333677763338878833
00000000388882333555555333333883333300333330333300000000307720333887823338788233388882333888723338878233387882333888823338887233
00000000338223333555555333333833333303333330333300000000330003333386233333822333338223333382233333862333338223333382233333822333
00000000333333333355553333333333333333333330333300000000333333333333333333333333333333333333333333333333333333333333333333333333
00000000333333333333333333333333333333333333333300000000333333333333333333333333333333333333333333333333333333333333333333333333
00000000333333333333333333333333000000000000000000000000f33333333333333333333333333333333333333333333333333333333333333333333333
000000003333333333373333333733330000000000000000000000008333333333e6833333ee833333ee833333ee833333e6833333ee833333ee833333ee8333
00000000333333333367333333373333000000000000000000000000033333333e7888333e8776333e777833367788333e8878333e8886333e88883336888833
00000000333333333637333333373333000000000000000000000000a33333333878883338788833368886333888783338887833388878333688863338788833
00000000e55555336337333333373333000000000000000000000000b33333333878823336888233388882333888853338887233367782333877723338877233
00000000333335333337333333373333000000000000000000000000933333333386233333822333338223333382233333862333338223333382233333822333
00000000333335333337333333373333000000000000000000000000433333333333333333333333333333333333333333333333333333333333333333333333
00000000333335333337333333373333000000000000000000000000433333333333333333333333333333333333333333333333333333333333333333333333
00000000333335333337333300000000000000000000000000000000333333333333333333333333333333333333333333333333333333333333333333333333
000000003333353333373333000000000000000000000000000000003333333333ee633333ee833333ee833333ee833333ee8333337e83333377633333e76333
00000000333335333337333300000000000000000000000000000000333333333e8887333e8888333e8888333e8888333788883337888833378888333e888633
00000000333335333363333300000000000000000000000000000000333333333888873338888633388888333688883336888833368888333888883338888633
00000000333335333633333300000000000000000000000000000000333333333888863338888633368882333688823336888233388882333888823338888233
00000000e55555336333333300000000000000000000000000000000333333333382233333822333336523333365233333622333338223333382233333822333
00000000333333333333333300000000000000000000000000000000333333333333333333333333333333333333333333333333333333333333333333333333
00000000333333333333333300000000000000000000000000000000e55555533333333333333333333333333333333333333333333333333333333333333333
000000003377a3333377633333aa933300000000000000000d030030000000003333333333333333333333333333333333333333333333333333333333333333
0000000037a5aa33371166333a66693300000000000000003dd3d03d0000000033e6833333ee833333ee833333ee833333e6833333ee833333ee833333ee8333
000000007a55aaa376661663a9996993000000000000000053d5d5dd500000003e8878333e8886333e888833368888333e7888333e8776333e77783336778833
00000000aaa5aaa366611663999669930000000000000000535535d3d00000003888783338887833368886333878883338788833387888333688863338887833
00000000aaa5aa93661666539999694300000000000000003d5d3d33d00000003888723336778233387772333887723338788233368882333888823338888233
000000003a555933361115333966643300000000000000005d3d5d35300000003386233333822333338223333382233333862333338223333382233333822333
0000000033a9933333655333339443330000000000000000535353d5300000003333333333333333333333333333333333333333333333333333333333333333
000000003333333333333333333333330000000000000000355333d3d00000003333333333333333333333333333333333333333333333333333333333333333
__sfx__
910600001863500000036000060001600006000160001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600002463500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600003064500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600003c64500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490400001845500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405
010200003061500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605
010200003061500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
910400001841500400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
490400001842500400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
010600001843500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010a00001845500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
