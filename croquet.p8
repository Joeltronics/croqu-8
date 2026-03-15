pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- all star croquet
-- by joel geddert

-- License: CC BY-NC-SA 4.0

--
-- Game core consts
--

DEBUG = false

-- Hide title screen components for capturing label image
CAPTURE_LABEL_IMAGE = false

BALL_R = 2.25
BALL_D = 2 * BALL_R
BALL_D2 = BALL_D*BALL_D

BALL_POLE_D = BALL_R + 0.125
BALL_POLE_D2 = BALL_POLE_D*BALL_POLE_D

MOVING_COOLDOWN_FRAMES = 60
SHOT_POWER_METER_RATE = 1/64
SHOT_POWER_METER_FALL_RATE = -1/32
SHOT_POWER_ERR_MAX_POWER = 10/360
SHOT_POWER_ERR_OVER = 20/360

ANGLE_STEP = 1/256

SQRT_MAX = sqrt(32767) - 0.001

DIFFICULTY_LABELS = {'player', 'easy', 'medium', 'hard', 'pro'}

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

OVER_POWER_SCREEN_SHAKE_TIME = 20
OVER_POWER_SCREEN_SHAKE_DIV = 5

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

over_power_screen_shake = 0

moving_cooldown = 0

cpu_draw = 0
cpu_update = 0

debug_last_dv = nil

turbo = false
debug_turbo = false
debug_pause_physics = false
debug_no_draw_tops = false
debug_draw_primitives = false
debug_increase_shot_pointer_length = false
-- debug_force_safe_rand = nil

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
	return (1 - t) * a + t * b
end

function lerp_round(a, b, t)
	return round(lerp(a, b, t))
end

-- Calculate distance, overflow-safe
-- In case of overflow or near-overflow, returns 32767
function distance(dx, dy)

	--[[
	Cases where this logic could still overflow:
	- If dx or dy is exactly -32768, abs() isn't safe
	- If scale is very large (more than ~23,000), then scale*sqrt would overflow

	However, playfield is 416x224, so this limits the max possible dx & dy we can actually see.
	So neither of these cases is actually possible in practice.

	Largest input case:
		dx, dy, scale = 416, 224, 4.16
		scaled dx, dy = 100, 53.8
		dx*dx + dy*dy = 10,107.7
		sqrt = 100.537
		scale * sqrt = 418.2

	Actual worst case:
		dx, dy, scale = 224, 224, 2.24
		scaled dx, dy = 100, 100
		dx*dx + dy*dy = 20,000
		sqrt = 141.4
		scale * sqrt = 141.4
	]]

	dx, dy = abs(dx), abs(dy)

	-- Keep as much precision as possible (don't scale unless needed), and also protect against divide-by-zero
	local scale = max(1, max(dx, dy) / 100)
	dx /= scale
	dy /= scale
	return scale * sqrt(dx*dx + dy*dy)
end

-- Calculate distance squared, overflow-safe
-- On overflow, returns 32767
function distance_squared(dx, dy)
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
	for i = 1,#items-1 do
		local any_swapped = false
		for j = 1,#items-i do
			local item1, item2 = items[j], items[j+1]
			if ((item1.z or item1.y) > (item2.z or item2.y)) then
				items[j], items[j+1] = item2, item1
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

				local dx, dy = ball.x - w.x, ball.y - w.y

				if dx == 0 and dy == 0 then
					-- Ball is on exactly the same spot, would get divide by zero
					ball.y += 1
					dy = ball.y - w.y
				end

				local d2 = distance_squared(dx, dy)

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

-- Returns true if any collisions occurred
function collisions()
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

	local incr = 0
	if (btnp(0)) incr -= 1
	if (btnp(1)) incr += 1

	if incr != 0 then
		if player.enabled then
			player.cpu_difficulty += incr
			if (player.cpu_difficulty < 0 or player.cpu_difficulty > 4) player.enabled = false
		else
			if incr > 0 then
				player.cpu_difficulty = 0
			else
				player.cpu_difficulty = 4
			end
			player.enabled = true
		end
	end

	num_players = 0
	for p in all(players) do
		if (p.enabled) num_players += 1
		p.cpu = p.enabled and p.cpu_difficulty > 0
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
		-- but this would not be fair when not using all players, some players would be more likely to start than others
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
	rectfill(0, 0, 127, 48, 12)
	fillp(0b0101101001011010)
	rectfill(0, 49, 127, 127, 0xD3)
	fillp()

	for y=51,127 do

		local w = 0.5 * (y - 48)
		local d = 1/w

		local stripe = ((128 * d + 1.5) % 2) >= 1
		if (y < 64) stripe = (y % 2) < 1

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

	-- Header
	sspr(0, 32, 128, 32, 0, 8)

	-- Pole

	local x1, x2, y1 = 30, 34, 47

	rectfill(x1, y1, x2, 128, 4)
	line(x1, y1, x1, 128, 9)
	line(x2, y1, x2, 128, 2)
	rectfill(x1+1, y1-2, x2-1, y1, 9)
	pset(x1, y1-1, 9)
	pset(x2, y1-1, 9)

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

		if not CAPTURE_LABEL_IMAGE then

			local col = p.color_main
			-- Print green player as white
			if (col == 11) col = 7

			local label = DIFFICULTY_LABELS[p.cpu_difficulty+1]
			if (not p.enabled) label, col = 'off', 6

			print('\^odff' .. label, 64 - 2*#label, py1, col)

			if idx == player_idx then
				print('⬅️', 64 - 20 - 4, py1, 7)
				print('➡️', 64 + 20 - 4, py1, 7)
			end
		end
	end

	if num_players > 0 and (time() % 1.0) > 0.5 and not CAPTURE_LABEL_IMAGE then
		print_centered('press 🅾️', 64, 100, 7)
	end

	if (DEBUG) print(round(stat(1) * 100), 116, 1, 8)

	pal(DISPLAY_PALETTE, 1)
end

function draw_game_finished()
	camera()

	poke(0x5f5f,0x10)
	pal(DISPLAY_PALETTE, 1)
	pal({[0]=0, 1, 2, -4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}, 2)
	memset(0x5f70, 0xff, 6)

	draw_title_screen_bg()

	-- Make sky a sunset instead

	local p1 = 0b1000001010000101
	local p2 = 0b1010010110100111
	local p3 = 0b1101011111111111

	local colors = {1, 3, 12, 14, 9}
	for idx = 1,#colors - 1 do
		local col, y = (16 * colors[idx + 1]) + colors[idx], 12 * (idx - 1)

		fillp(p1)
		rectfill(0, y, 127, y+3, col)
		fillp(p2)
		rectfill(0, y+4, 127, y+7, col)
		fillp(p3)
		rectfill(0, y+8, 127, y+11, col)
	end
	fillp()

	for p in all(players) do
		if (p.enabled) assert(p.finish_position)
	end

	local y = 49
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

		local col = player.color_main
		-- Print green player as white
		if (col == 11) col = 7
		print_centered(DIFFICULTY_LABELS[player.cpu_difficulty+1], 64, y, col)

		print_centered(player.total_turns, 88, y, 7)
		print_centered(player.total_shots, 112, y, 7)

		y += 8
	end

	print_centered('press 🅾️ to restart', 64, 110, 7)

	if (DEBUG) print(round(stat(1) * 100), 116, 1, 8)
end

--
-- CPU AI logic
--

function cpu_get_target(player)
	local player_ball, next_wicket, difficulty = player.ball, WICKETS[player.last_wicket_idx + 1], player.cpu_difficulty

	for ball in all(balls) do
		ball.cpu_target_score = nil
	end

	local tx, ty = next_wicket[1], next_wicket[2]
	local dx, dy = tx - player_ball.x, ty - player_ball.y
	local d = distance(dx, dy)

	local shots = player.shots + (player.bonus_shots or 0)

	-- Determine a few flags that will be used later
	local easy_shot, wrong_side, target_angle_deg = cpu_check_next_wicket_flags(next_wicket, dx, dy, d)
	local clear_shot = nearest_ball_distance(player_ball) > AI_CLEAR_SHOT_MIN_BALL_DISTANCE
	local target_blocked = wicket_between(player_ball, tx, ty, 0) and not (abs(dx) < 3 and abs(dy) < 4)

	-- Positive = ahead, negative = behind. Increase our effective score by 1 for every 2 shots
	local lead_point_gap = calculate_lead_point_gap() + shots \ 2

	-- With no other balls in the way, this CPU player is too good - it can win before another player has a chance
	-- But it does much worse when other balls are involved
	-- So add a bit of handicap when there are no other balls anywhere close
	-- Also add this slop when way ahead of everyone
	-- There will be an extra modifier later once we know if we're targeting a ball
	-- (But have to calculate the base first, because it may affect whether to target a ball)
	local BASE_SLOP_WITH_DIFFICULTY = {1, 1, 0, -10}
	local slop = BASE_SLOP_WITH_DIFFICULTY[difficulty]
	if (clear_shot) slop += 1
	if (lead_point_gap >= 7) slop += 1
	if (lead_point_gap >= 5) slop += 1
	if (lead_point_gap >= 3) slop += 1
	if (lead_point_gap <= -2) slop -= 1
	if (lead_point_gap <= -5) slop -= 1

	-- Check if we're the last remaining player
	if (num_players_finished >= num_players - 1) lead_point_gap, slop = 0, -10

	-- First determine ideal target point for next wicket, without accounting for other balls
	-- This is probably slightly past it, or slightly in front of it

	-- First, see if we're lined up in a way that can score 2 wickets at once - if so, use next wicket as target
	-- TODO: also try for 2 wickets + pole in some cases
	local targeting_thru

	-- easy_shot is probably redundant here
	if difficulty > 1 and (easy_shot or dy < 6 or target_angle_deg < 15) and not (wrong_side or next_wicket.pole) then

		local next_wicket_after = WICKETS[player.last_wicket_idx + 2]
		assert(next_wicket_after)

		local tx_next, ty_next = next_wicket_after[1], next_wicket_after[2]

		local distance_off_from_current_target = distance_to_line_segment(
			tx, ty, player_ball.x, player_ball.y, tx_next, ty_next) or 32767

		if distance_off_from_current_target < 4 and not wicket_between(player_ball, tx_next, ty_next, 0.25) then
			tx, ty = tx_next, ty_next
			dx, dy = tx - player_ball.x, ty - player_ball.y
			d = distance(dx, dy)
			easy_shot = false
			targeting_thru = next_wicket_after
			-- Note we intentionally don't reset any of the other flags, those should still refer to nearest
		end
	end

	local target_distance_past, play_safe_chance = 0, nil

	if (easy_shot and not wrong_side) or next_wicket.pole then
		-- Easy shot, or targeting a pole; no point trying any of the play-safe logic
		target_distance_past = AI_TARGET_PAST_WICKET_POLE_DISTANCE

	elseif target_angle_deg < 120 then
		-- If wrong side of wicket (by a lot), keep targeting center of wicket; otherwise:

		-- Determine odds of playing it safe (targeting in front of wicket instead of trying to go through)
		-- TODO: would be good to refactor this into a function, but we're right at the token limit

		if target_blocked or (player.bonus_shots or 0) >= 2 then
			-- If target blocked, always play safe
			-- Or if we have bonus shots we will lose on going through wicket, so no reason not to play this shot safe
			-- TODO: don't do this when there's a ball in the way of the next wicket - would rather target that ball,
			-- and targeting in front could make that not happen in some cases
			play_safe_chance = 1

		else
			-- 30: 0
			-- 60: 1
			local angle_factor = max(0, target_angle_deg - 30) / 60

			-- 32: 0
			-- 96: 1
			local distance_factor = max(0, d - 32) / 64

			if (difficulty <= 1) distance_factor *= 4

			play_safe_chance = 2 * angle_factor * distance_factor

			-- Slop factor - safer when shot will be less accurate
			local slop_factors = { 1, 1.125, 1.25, 1.5 }
			play_safe_chance *= slop_factors[clip_num(flr(slop) + 1, 1, 4)]

			-- Extra shots factor
			local shots_factors = {1, 1.5, 2}
			play_safe_chance *= shots_factors[clip_num(shots, 1, 3)]

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
			if shots <= 1 and target_nearest_ball_d <= 64 then
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

		if targeting_thru then
			play_safe_chance *= 2
			if (difficulty <= 2) play_safe_chance = 1
		end

		-- If play_safe_chance < 10% or > 90%, snap to 0 or 1
		-- local r = debug_force_safe_rand or rnd()
		local r = rnd()
		if (play_safe_chance > 0.9) or (play_safe_chance >= 0.1 and play_safe_chance >= r) then

			-- Target in front of wicket

			for i = 1,6 do

				local tx_was, target_blocked_was = tx, target_blocked

				if next_wicket.reverse then
					tx += AI_TARGET_AHEAD_OF_WICKET_DISTANCE
				else
					tx -= AI_TARGET_AHEAD_OF_WICKET_DISTANCE
				end

				-- Update target_blocked for new target
				target_blocked = wicket_between(player_ball, tx, ty, 0)

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

	local target_ball, next_wicket_score

	if target_blocked or targeting_thru or not player.bonus_shots then
		-- No bonus shots yet, so target another ball to get them
		-- Or target is blocked, so target another ball because it's likely the only option

		-- TODO: if targeting_thru, would be better to use the following wicket as the target here, not the current wicket.
		-- The tricky part is we need to make sure we don't miss the current wicket. Right now there is very basic logic
		-- to try and target through in certain very specific cases.
		target_ball, next_wicket_score = cpu_target_ball(player_ball, next_wicket, targeting_thru, wrong_side, easy_shot, target_blocked, difficulty)

		if target_ball then
			tx, ty = cpu_adjust_target_for_ball(player_ball, tx, ty, target_ball, 0.5)
		end
	end

	-- Check if there's a ball between here and whatever is the current target
	-- If so, target that ball instead

	local other_ball_margin = 2
	if (d <= 16) other_ball_margin = 0

	local target_distance_past_ball = AI_TARGET_PAST_BALL_DISTANCE

	local target_ball_between = ball_between(player_ball, tx, ty, other_ball_margin)
	if target_ball_between then
		target_ball = target_ball_between
		-- We want to move ball out of the way, so target further away from ball center than other case, and hit harder
		tx, ty = cpu_adjust_target_for_ball(player_ball, tx, ty, target_ball, 1)
	end

	--
	-- Target slightly past chosen point
	--

	local tx_orig, ty_orig = tx, ty

	-- If there's a ball in between us and the intended target, hit it a bit harder to help clear it
	-- Also, hardest AI always does this - not just to play mean (but that too),
	-- but also because it's very accurate so it can get away with it
	if (target_ball_between or difficulty >= 4) target_distance_past_ball *= 2

	if (target_ball) target_distance_past = target_distance_past_ball

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

	target_power, target_angle = cpu_add_error(target_power, target_angle, slop)

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
		targeting_ball=target_ball,
		target_ball_between=target_ball_between,
		lead_point_gap=lead_point_gap,
		play_safe_chance=play_safe_chance,
		next_wicket_score=next_wicket_score,
	}
end

function cpu_adjust_target_for_ball(player_ball, tx, ty, target_ball, r)

	local tx_new, ty_new = target_ball.x, target_ball.y

	-- If the ball is reasonably close, then don't target it head-on - adjust angle a smidge toward previous tx/ty
	-- If it's quite far away, then skip this because we don't want to miss!
	if distance(target_ball.x - player_ball.x, target_ball.y - player_ball.y) <= 64 then
		local dx, dy = tx - target_ball.x, ty - target_ball.y
		local d = distance(dx, dy)
		if d then
			local scale = r * BALL_R / d
			tx_new += dx * scale
			ty_new += dy * scale
		end

		-- Don't do this if it wasn't blocked before, but is now
		-- TODO: account for slop here?
		if (wicket_between(player_ball, tx_new, ty_new, 0) and not wicket_between(player_ball, tx, ty, 0)) return tx, ty
	end

	return tx_new, ty_new
end

-- Returns easy_shot, wrong_side, target_angle_deg
function cpu_check_next_wicket_flags(next_wicket, dx, dy, d)

	if (next_wicket.pole) return (d < 16), false, 0

	if (next_wicket.reverse) dx = -dx

	local target_angle_deg = abs(((360*atan2(dx, dy) + 180) % 360) - 180)

	local easy_shot = (abs(dx) < 16 and target_angle_deg < 30) or (abs(dx) < 8 and abs(dy) < 4)

	return easy_shot, (dx < 0), target_angle_deg
end

function cpu_target_past(player_ball, tx, ty, extra_distance)
	local dx, dy = tx - player_ball.x, ty - player_ball.y
	local d = distance(dx, dy)
	return tx + extra_distance * (dx / d), ty + extra_distance * (dy / d)
end

function cpu_shift_y_away_from_center_of_wicket(dy)

	if (dy > 16) return 2
	if (dy < -16) return -2
	if (dy > 4) return 1
	if (dy < -4) return -1

	return 0
end

function nearest_ball_distance(ball, x, y)
	x, y = x or ball.x, y or ball.y
	local d = 32767
	for other_ball in all(balls) do
		if (other_ball != ball) d = min(d, distance(x - other_ball.x, y - other_ball.y))
	end
	return d
end

function calculate_lead_point_gap()

	local max_other_player_wicket = 0

	for i = 1,#players do
		local p = players[i]
		if i != player_idx and p.enabled and not p.finish_position then
			max_other_player_wicket = max(max_other_player_wicket, p.last_wicket_idx)
		end
	end

	return players[player_idx].last_wicket_idx - max_other_player_wicket
end

-- (px, py): point
-- (x1, x2) & (x2, y2): line segment ends
-- d_min & d_max: optional extra length to subtract from each end of line segment
function distance_to_line_segment(
		px, py,
		x1, y1,
		x2, y2,
		d_min, d_max)

	local line_dx, line_dy = x2 - x1, y2 - y1

	local d2 = distance_squared(line_dx, line_dy)
	assert(d2 >= 0)
	if (d2 == 0) return nil
	local d = sqrt(d2)

	local t_min, t_max = 0, 1
	if (d_min) t_min = d_min / d
	if (d_max) t_max = 1 - (d_max / d)
	if (t_min >= t_max or t_max <= 0 or t_min >= 1) return nil

	local point_dx = px - x1
	local point_dy = py - y1

	-- Project point onto the line

	-- First, determine interpolation parameter along line segment: t = 0 at (x1, y1), 1 at (y2, y2)
	-- t = (dot product) / (line length ^ 2)
	local t = (point_dx * line_dx + point_dy * line_dy) / d2

	-- If t is not in range [t_min, t_max], then projected point is beyond ends of line segment
	if (t <= t_min or t >= t_max) return nil

	-- Project it onto line segment, and check distance from projected point
	local proj_x = lerp(x1, x2, t)
	local proj_y = lerp(y1, y2, t)
	return distance(px - proj_x, py - proj_y)
end

function wicket_between(ball, tx, ty, margin)
	for wicket in all(WICKET_COLLISION_POINTS) do
		-- Hidden wickets would be redundant
		-- TODO optimization: instead, maintain separate list of non-hidden wickets and just iterate that
		-- Also, if this wicket is exactly the target (i.e. a pole), then skip it
		if (not wicket.hidden) and (tx != wicket.x or ty != wicket.y or not wicket.pole) then
			local d_between = distance_to_line_segment(
				wicket.x, wicket.y,
				ball.x, ball.y,
				tx, ty) or 32767
			if (d_between < BALL_POLE_D + margin) return true
		end
	end
	return false
end

function ball_between(ball, tx, ty, margin)
	-- Checks if there are any balls between ball & target. If so, returns the ball (of these) that is closest to ball

	local closest_ball = nil
	local closest_ball_d2 = 32767

	for other_ball in all(balls) do
		if other_ball != ball then
			local d_between = distance_to_line_segment(
				other_ball.x, other_ball.y,	
				ball.x, ball.y,
				tx, ty,
				BALL_R, nil) or 32767

			if (d_between < BALL_POLE_D + margin) then
				local other_ball_d2 = distance_squared(other_ball.x - ball.x, other_ball.y - ball.y)
				if (other_ball_d2 < closest_ball_d2) closest_ball, closest_ball_d2 = other_ball, other_ball_d2
			end
		end
	end

	return closest_ball
end

function is_safe_to_target_thru(player_ball, other_ball, next_wicket, wicket_targeting_thru)
	if (not wicket_targeting_thru) return true
	-- We want to make sure next_wicket is in between player_ball and other_ball
	return distance_to_line_segment(
		next_wicket[1], next_wicket[2],
		player_ball.x, player_ball.y,
		other_ball.x, other_ball.y) or 32767 < 4
end

function cpu_target_ball(player_ball, next_wicket, wicket_targeting_thru, wrong_side, easy_shot, target_blocked, difficulty)

	if (difficulty <= 2) wicket_targeting_thru = nil

	local target = wicket_targeting_thru or next_wicket
	local tx, ty = target[1], target[2]
	local dx_self_target, dy_self_target = tx - player_ball.x, ty - player_ball.y
	local d_self_target = distance(dx_self_target, dy_self_target)

	if (d_self_target < 1) return nil, d_self_target

	-- How much extra margin we need to not consider this ball blocked by a wicket
	local wicket_margin = 1.5

	-- Only target a ball if the score is less than this
	local next_wicket_score = d_self_target

	-- Make it less likely to target another ball when going for a pole
	if (next_wicket.pole) next_wicket_score *= 0.5

	if wrong_side or target_blocked then
		-- In one of these cases always go for closest ball, within a reasonable range
		next_wicket_score = 128
	elseif easy_shot then
		-- May still want to target another ball just to move it
		-- But only if it's not far out of the way, and safe (extra wicket margin)
		next_wicket_score, wicket_margin = min(next_wicket_score, 24), 2
	end
	next_wicket_score = min(next_wicket_score, 128)

	-- Less likely to target a ball at easier difficulties
	local difficulty_scale_next_wicket_score = {0.5, 0.9, 1.0, 1.0}
	next_wicket_score *= difficulty_scale_next_wicket_score[difficulty]

	-- Figure out best ball to target for bonus shot
	local best_score = next_wicket_score
	local target_ball
	for b in all(balls) do
		if b != player_ball and is_safe_to_target_thru(player_ball, b, next_wicket, wicket_targeting_thru) and not wicket_between(player_ball, b.x, b.y, wicket_margin) then

			local dx_ball, dy_ball = b.x - player_ball.x, b.y - player_ball.y
			local d_ball_self = distance(dx_ball, dy_ball)

			local dx_target = b.x - tx
			local d_ball_target = distance(dx_target, b.y - ty)

			local score = d_ball_self + d_ball_target
			assert(score > 0) -- check overflow didn't happen
			score -= d_self_target
			assert(score > 0)
			score += min(d_ball_self, 2 * d_ball_target)
			assert(score > 0)

			-- Penalize if other ball is on wrong side of target, unless we can shoot it through (or we're also on wrong side)
			local can_shoot_through = abs(dy_self_target) < 5 and abs(dy_ball) < 10
			if not (next_wicket.pole or wrong_side or can_shoot_through) then
				if ((not next_wicket.reverse) and dx_target > 2) score *= 2
				if (next_wicket.reverse and dx_target < -2) score *= 2
			end

			b.cpu_target_score = score

			if score < best_score then
				-- This is the best candidate so far
				target_ball, best_score = b, score
			end
		end
	end

	return target_ball, next_wicket_score
end

function cpu_determine_target_power_angle(player_ball, tx, ty, target_ball)

	local dx, dy = tx - player_ball.x, ty - player_ball.y
	local d, target_angle = distance(dx, dy), atan2(dx, dy)
	local target_power = sqrt(d) / 14

	-- If we're targeting a nearby ball, increase power
	-- Note that "cpu_target_past" has already been handled, so don't need to add extra for that
	if target_ball then
		if (d < 32) target_power *= 1.5
		if (d < 16) target_power *= 1.333333333
	end

	-- Minimum power is 1/64, maximum is 63/64
	return clip_num(target_power, SHOT_POWER_METER_RATE, 1-SHOT_POWER_METER_RATE), target_angle
end

function cpu_add_error(target_power, target_angle, slop)

	slop = max(0, slop)

	local r, angle_err_step = slop * (rnd() - 0.5), 0
	if abs(r) > 0.4 then
		angle_err_step = 2
	elseif abs(r) > 0.25 then
		angle_err_step = 1
	end

	-- When slop is quite high, always add a bit of error
	if (slop >= 3) angle_err_step = max(1, angle_err_step)

	-- Increase/decrease angle error depending on distance
	-- (slop is less believable at short distances)
	if (target_power > 0.75) angle_err_step *= 1.5
	if (target_power < 0.25) angle_err_step *= 0.5
	if (target_power < 0.125) angle_err_step *= 0.5

	target_angle += sgn(r) * angle_err_step * ANGLE_STEP

	target_power += slop * (rnd() - 0.5) / 32

	return target_power, target_angle % 1.0
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
		sfx(11)
		if (player == players[player_idx]) player.shots += 1
		player.bonus_shots = nil

	else
		-- Last wicket; finish the game for this player
		sfx(12)
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
	players, balls, WICKET_COLLISION_POINTS, num_players_finished, player_idx, game_started, game_finished = {}, {}, {}, 0, 1, false, false

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
			-- cpu_difficulty: 0 = player, 1 = easiest, 4 = hardest
			-- Default to 1 human player, others are medium difficulty
			cpu_difficulty=idx > 1 and 2 or 0,
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

	local x, y, xp, wx, wy = ball.x, ball.y, ball.x_prev, w[1], w[2]

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
		-- Range: [1.0, 1.0) * SHOT_POWER_ERR_OVER
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

	sfx(clip_num(flr(shot_power * 4), 0, 3))
	sfx(clip_num(7 + flr(shot_power * 4), 7, 10))

	if (shot_power_over) over_power_screen_shake = OVER_POWER_SCREEN_SHAKE_TIME
end

function _update60()

	do_update()
	local cpu_update_one = stat(1)

	if turbo or debug_turbo then
		while stat(1) < (0.98 - cpu_draw - cpu_update_one) do
			do_update()
		end
	end

	cpu_update = stat(1)
end

function do_update()

	local player = players[player_idx]
	local player_ball, left, right, up, down, op, x = player.ball, btn(0), btn(1), btn(2), btn(3), btnp(4), btn(5)

	turbo = player.cpu and x and btn(4)

	if game_finished then
		if (op) run()
		return
	end

	if DEBUG then
		while stat(30) do
			local key = stat(31)
			if (key == '`') debug_turbo = not debug_turbo
			if (key == '1') debug_draw_primitives = not debug_draw_primitives
			if (key == '2') debug_increase_shot_pointer_length = not debug_increase_shot_pointer_length
			if (key == '3') debug_no_draw_tops = not debug_no_draw_tops
			if (key == '=') debug_pause_physics = not debug_pause_physics

			if game_started and moving_cooldown <= 0 then

				local update_cpu_target = false

				-- if (key == '6') player.last_wicket_idx = #WICKETS - 1

				-- if (key == '7') player.bonus_shots, update_cpu_target = nil, true
				-- if (key == '8') player.bonus_shots, update_cpu_target = 0, true
				-- if (key == '9') player.bonus_shots, update_cpu_target = 1, true
				-- if (key == '0') player.bonus_shots, update_cpu_target = 2, true

				-- if key == 'i' then
				-- 	if debug_force_safe_rand == 0 then
				-- 		debug_force_safe_rand = nil
				-- 	else
				-- 		debug_force_safe_rand = 0
				-- 	end
				-- 	update_cpu_target = true
				-- end
				-- if key == 'o' then
				-- 	if debug_force_safe_rand == 1 then
				-- 		debug_force_safe_rand = nil
				-- 	else
				-- 		debug_force_safe_rand = 1
				-- 	end
				-- 	update_cpu_target = true
				-- end

				if key == '[' then
					player.last_wicket_idx += 1
					update_cpu_target = true
				end

				if key == ']' then
					next_player()
					player = players[player_idx]
					player_ball = player.ball
					update_cpu_target = true
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
					update_cpu_target = true
				end

				if (update_cpu_target and player.cpu) player.cpu_target = cpu_get_target(player)
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

				if (not player.cpu_target) player.cpu_target = cpu_get_target(player)

				if shot_power_change == 0 then
					local angle_err_step = ((shot_angle - player.cpu_target.angle + 0.5) % 1.0) - 0.5
					if angle_err_step >= ANGLE_STEP then
						right = true
					elseif angle_err_step <= -ANGLE_STEP then
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

						local drag, x, y = DRAG, ball.x, ball.y
						if (x < ROUGH or y < ROUGH or x >= WIDTH-ROUGH or y >= HEIGHT-ROUGH) drag = DRAG_ROUGH

						ball.vx *= drag
						ball.vy *= drag

						local v2 = ball.vx*ball.vx + ball.vy*ball.vy
						if (v2 <= V2_STOP_THRESH) then
							-- Stop ball
							ball.vx, ball.vy = 0, 0

							-- Move ball slightly when it stops
							if not any_collisions_for_ball(ball) then
								ball.x = round(x + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
								ball.y = round(y + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
								local x2, y2 = ball.x, ball.y
								resolve_all_static_collisions_for_ball(ball)
								-- If static collisions caused significant movement, forget about the stop movement
								-- entirely - go back to original position
								if distance_squared(ball.x - x2, ball.y - y2) > 1 then
									ball.x, ball.y = x, y
								end
							end
						end
						moving_cooldown = MOVING_COOLDOWN_FRAMES
					end
				end
			end

			for p in all(players) do
				check_wickets(p)
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
end

function update_select_starting_point()
	local player = players[player_idx]
	local player_ball = player.ball

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
	local dx, dy = cos(shot_angle), sin(shot_angle)

	local l = 24
	if (debug_increase_shot_pointer_length) l = 256

	line_round(x, y, x + l*dx, y + l*dy, shot_power_color())
end

function draw_club()

	local player = players[player_idx]
	assert(player.ball)
	local x, y = player.ball.x, player.ball.y
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

	local c1x, c1y, c2x, c2y, c3x, c3y, c4x, c4y = c[1][1], c[1][2], c[2][1], c[2][2], c[3][1], c[3][2], c[4][1], c[4][2]

	-- Fill
	pelogen_tri_low(c1x, c1y, c2x, c2y, c3x, c3y, 4)
	pelogen_tri_low(c3x, c3y, c4x, c4y, c1x, c1y, 4)

	-- Sides - (pelogen_tri_low seems to have different rounding behavior, so these aren't necessarily covered)
	line(c1x, c1y, c2x, c2y, 4)
	line(c3x, c3y, c4x, c4y, 2)

	-- Ends
	line_round(c1x, c1y, c4x, c4y, 5)
	line_round(c2x, c2y, c3x, c3y, 5)

	-- Stripes in player color
	for i in all({1, 4}) do
		local x1, y1 = lerp_round(c1x, c2x, i/5), lerp_round(c1y, c2y, i/5)
		local x2, y2 = lerp_round(c4x, c3x, i/5), lerp_round(c4y, c3y, i/5)
		line(x1, y1, x2, y2, player.color_main)
		pset(x1, y1, player.color_light)
		pset(x2, y2, player.color_dark)
	end
end

function draw_status_bar()

	rectfill(1, 1, STATUS_BAR_WIDTH - 1, 128, 4)
	line(STATUS_BAR_WIDTH, 1, STATUS_BAR_WIDTH, 128, 2)
	line(0, 1, 0, 128, 9)
	line(0, 0, STATUS_BAR_WIDTH, 0, 9)
	ovalfill(0, -2, STATUS_BAR_WIDTH, 2, 9)
	pset(0, 0, 10)
	pset(STATUS_BAR_WIDTH, 0, 4)

	for idx = 1,#players do
		local p, y1, textcol = players[idx], 9*idx + 1, 7
		if (p.color_main >= 9) textcol = 0

		palt()
		pal(p.palette)
		sspr(40, 8, 9, 9, 0, y1-2)
		reset_palette()
		if (p.enabled) print_centered(p.last_wicket_idx - 1, 5, y1+1, textcol)

		local x = STATUS_BAR_WIDTH + 4

		if p.finish_position then
			if p.finish_position <= 3 then
				spr(48 + p.finish_position, x - 2, y1 - 1)
			else
				rectfill(x-1, y1-1, x+3, y1+5)
				print(p.finish_position, x, y1, 7)
			end

		elseif idx == player_idx then
			pal(p.ball.palette)
			for i = 1,p.shots do
				spr(30, x-3, y1 - 1)
				x += 6
			end
			reset_palette()

			if p.bonus_shots then
				for i=1,2 do
					if (i <= p.bonus_shots) then
						pal(p.ball.palette)
						spr(7, x-3, y1 - 1)
						reset_palette()
						circ(x, y1 + 2, 2, textcol)
					else
						circ(x, y1 + 2, 2, textcol)
					end
					x += 6
				end
			end
		end
	end

	-- Shot power meter
	if shot_power > 0 or shot_power_change != 0 then
		local col = shot_power_color()
		local x_offset = -((over_power_screen_shake \ OVER_POWER_SCREEN_SHAKE_DIV) % 2)
		local y = 125 - 60*shot_power
		rectfill(3 + x_offset, y, 5 + x_offset, 127, col)
		rect(2 + x_offset, 64, 6 + x_offset, 128, 0)
		print('◀', STATUS_BAR_WIDTH - 1 + x_offset, y-2, col)
	end

	-- Grass in corner
	if not debug_draw_primitives then
		palt()
		spr(54, 0, 124, 2, 1)
		reset_palette()
	end

	over_power_screen_shake = max(over_power_screen_shake - 1, 0)
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

	-- Grass
	for y=0,ceil((HEIGHT-2*ROUGH)/16) do
		for x=0,ceil((WIDTH-2*ROUGH)/16) do
			local fp = 0b0101101001011010
			if (x % 2 == 0 and y % 2 == 0) fp = 0x0000
			if (x % 2 == 1 and y % 2 == 1) fp = 0xFFFF
			fillp(fp)
			local off = ROUGH
			rectfill(x*16 + off, y*16 + off, x*16 + 16 + off, y*16 + 16 + off, 0xD3)
		end
	end
	fillp(ROUGH_FILLP)
	rectfill(0, 0, WIDTH, ROUGH-1, ROUGH_COLOR)
	rectfill(0, HEIGHT - ROUGH, WIDTH, HEIGHT, ROUGH_COLOR)
	rectfill(0, ROUGH, ROUGH, HEIGHT - ROUGH, ROUGH_COLOR)
	rectfill(WIDTH - ROUGH, ROUGH, WIDTH, HEIGHT - ROUGH, ROUGH_COLOR)
	fillp()

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

	-- Draw arrow under next wicket
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

	-- Starting point area, or shot line
	if not player.selected_starting_point then
		x, y = player_ball.x - 3, player_ball.y - 3
		spr(5, x, y - 12)
		spr(5, x, y + 12, 1, 1, false, true)
	elseif moving_cooldown <= 0 then
		draw_shot()
	end

	--[[
	Balls & wickets - stuff where Z-order matters

	TODO optimizations: (Bubblesort is slow, O(n^2))
	- Do not add offscreen sprites to list
	- Sort list of wickets at init, then they're already sorted
	- Sort list each time we add a sprite
	]]

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

	if not (debug_no_draw_tops or debug_draw_primitives) then
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

	sort_z(sprites)

	for s in all(sprites) do
		if (s.pal) pal(s.pal)
		spr(s.idx, round(s.x), round(s.y), s.w or 1, s.h or 1)
		if (s.pal) reset_palette()
	end

	-- CPU target
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

	-- Debug primitives
	if debug_draw_primitives then

		for ball in all(balls) do
			local x, y = ball.x, ball.y

			-- Velocity
			line_round(
				x,
				y,
				x + 30*ball.vx,
				y + 30*ball.vy,
				11)

			-- Current collisions
			for coll in all(ball.collisions) do

				-- Normal: orange
				if (coll.nx) line_round(x, y, x + 16*coll.nx, y + 16*coll.ny, 9)

				-- v before: blue
				if (coll.vx_before) line_round(x, y, x - 30 * coll.vx_before, y - 30*coll.vy_before, 12)

				-- v after: red
				if (coll.vx_after) line_round(x, y, x + 30 * coll.vx_after, y + 30*coll.vy_after, 8)

				line_round(x, y, coll.x, coll.y, 14)
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

	-- Club
	if (player.selected_starting_point and moving_cooldown <= 0) draw_club()

	-- HUD
	camera()
	draw_status_bar()

	-- Debug text overlays
	-- (Many of these are commented out to save tokens)
	if DEBUG then

		if debug_pause_physics then
			print_centered('paused', 64, 0, 8)
		end

		cursor(96, 1, 8)

		-- print('mem:' .. stat(0))
		local cpu = stat(1)
		cpu_draw = cpu - cpu_update
		-- print('cpu:' .. round(cpu * 100) .. '=' .. round(cpu_update * 100) .. '+' .. round(cpu_draw * 100))
		print(round(cpu * 100))

		if not player.finish_position then

			-- print('x=' .. player_ball.x)
			-- print('y=' .. player_ball.y)
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
				-- print('tx=' .. player.cpu_target.x)
				-- print('ty=' .. player.cpu_target.y)
				-- print('td=' .. player.cpu_target.d)
				-- print('tp=' .. player.cpu_target.power)
				-- print('ta=' .. (player.cpu_target.angle * 360))
				-- print('deg=' .. player.cpu_target.target_angle_deg)

				if (player.cpu_target.easy_shot) print('easy_shot')
				if (player.cpu_target.target_blocked) print('target_blocked')
				if (player.cpu_target.wrong_side) print('wrong_side')
				if (player.cpu_target.clear_shot) print('clear_shot')
				if (player.cpu_target.targeting_ball) print('targeting_ball')
				if (player.cpu_target.target_ball_between) print('tbb')

				-- print('gap=' .. player.cpu_target.lead_point_gap)
				print('slop=' .. player.cpu_target.slop)

				if (player.cpu_target.play_safe_chance) print('saf=' .. player.cpu_target.play_safe_chance)

				color(7)
				if (player.cpu_target.next_wicket_score) print(player.cpu_target.next_wicket_score)

				-- for ball in all(balls) do
				for p in all(players) do
					color(p.color_main)
					local b = p.ball
					if (b and b.cpu_target_score) print(b.cpu_target_score)
				end
			end
		end
	end

	-- Set display palette at very end
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
0000000033333333333333333333333300000000e000000020000000f33333333333333333333333333333333333333333333333333333333333333333333333
0000000033333333333733333337333300000000e8000008200000008333333333e6833333ee833333ee833333ee833333e6833333ee833333ee833333ee8333
0000000033333333336733333337333300000000e888888820000000033333333e7888333e8776333e777833367788333e8878333e8886333e88883336888833
0000000033333333363733333337333300000000e888888820000000a33333333878883338788833368886333888783338887833388878333688863338788833
00000000e5555533633733333337333300000000e888888820000000b33333333878823336888233388882333888853338887233367782333877723338877233
0000000033333533333733333337333300000000e888888820000000933333333386233333822333338223333382233333862333338223333382233333822333
0000000033333533333733333337333300000000e888888820000000433333333333333333333333333333333333333333333333333333333333333333333333
00000000333335333337333333373333000000000888888800000000433333333333333333333333333333333333333333333333333333333333333333333333
00000000333335333337333300000000000000000088888000000000333333333333333333333333333333333333333333333333333333333333333333333333
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
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccc77cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccc77777ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccc7777777cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77cccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77777ccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc7777777cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccc000ccc00ccccc00cccccccccccc0000cc000000cccacccc000000ccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccc00c00cc00ccccc00ccccccccccc00cc00ccc00ccccaaaccc00ccc00cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccc00ccc00c00ccccc00ccccccccccc00ccccccc00ccaaaaaaac00ccc00cccccccccccccccccccccccccccccccccccc
cccc77cccccccccccccccccccccccccccccc00ccc00c00ccccc00cccccccccccc0000cccc00cccaaaaacc000000ccccccccccccccccccccccccccccccccccccc
cc77777ccccccccccccccccccccccccccccc0000000c00ccccc00ccccccccccccccc00ccc00ccccaaaccc00c00cccccccccccccccccccccccccccccccccccccc
c7777777cccccccccccccccccccccccccccc00ccc00c00ccccc00ccccccccccc00cc00ccc00cccaaaaacc00cc00ccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccc00ccc00c000000c000000cccccccc0000cccc00cccaacaacc00ccc00cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccffffccc888888cccccccccccccccaaaaccc7ccccc7ccbbbbbbbc549444945cccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccffffffcc8888888cccccccccccccaaaaaacc7ccccc7cbbbbbbbbc549444945cccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccfffccfffc88ccc888ccc55650cccaaaccaaac7ccccc7cbbccccccccccc4ccccccccccccccccccccccccccccccc77ccc
cccccccccccccccccccccccccccccccccffccccffc88cccc88cc5060000ccaaccccaac7ccccc7cbbccccccccccc4ccccccccccccccccccccccccccccc77777cc
cccccccccccccccccccccccccccccccccffccccccc88cccc88c500700000caaccccaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccc7777777c
cccccccccccccccccccccccccccccccccffccccccc88ccc888c000700000caaccccaac7ccccc7cbbbbbbbcccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccffccccccc8888888cc000700000caaccccaac7ccccc7cbbbbbbbcccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccffccccccc8888888cc000700000caaccccaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccffccccffc88ccc888c000700001caacccaaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccfffccfffc88cccc88cc0060001ccaaacaaacc7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccffffffcc88cccc88ccc00601ccccaaaaaaac7ccccc7cbbbbbbbbccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccffffccc88cccc88cccccccccccccaaacaac7777777ccbbbbbbbccccc4ccccccc77ccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77777cccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc7777777ccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
__label__
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccc77cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccc77777ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccc7777777cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77cccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77777ccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc7777777cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccc000ccc00ccccc00cccccccccccc0000cc000000cccacccc000000ccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccc00c00cc00ccccc00ccccccccccc00cc00ccc00ccccaaaccc00ccc00cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccc00ccc00c00ccccc00ccccccccccc00ccccccc00ccaaaaaaac00ccc00cccccccccccccccccccccccccccccccccccc
cccc77cccccccccccccccccccccccccccccc00ccc00c00ccccc00cccccccccccc0000cccc00cccaaaaacc000000ccccccccccccccccccccccccccccccccccccc
cc77777ccccccccccccccccccccccccccccc0000000c00ccccc00ccccccccccccccc00ccc00ccccaaaccc00c00cccccccccccccccccccccccccccccccccccccc
c7777777cccccccccccccccccccccccccccc00ccc00c00ccccc00ccccccccccc00cc00ccc00cccaaaaacc00cc00ccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccc00ccc00c000000c000000cccccccc0000cccc00cccaacaacc00ccc00cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccssssccc888888cccccccccccccccaaaaccc7ccccc7ccbbbbbbbc549444945cccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccsssssscc8888888cccccccccccccaaaaaacc7ccccc7cbbbbbbbbc549444945cccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccsssccsssc88ccc888ccc55650cccaaaccaaac7ccccc7cbbccccccccccc4ccccccccccccccccccccccccccccccc77ccc
cccccccccccccccccccccccccccccccccssccccssc88cccc88cc5060000ccaaccccaac7ccccc7cbbccccccccccc4ccccccccccccccccccccccccccccc77777cc
cccccccccccccccccccccccccccccccccssccccccc88cccc88c500700000caaccccaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccc7777777c
cccccccccccccccccccccccccccccccccssccccccc88ccc888c000700000caaccccaac7ccccc7cbbbbbbbcccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccssccccccc8888888cc000700000caaccccaac7ccccc7cbbbbbbbcccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccssccccccc8888888cc000700000caaccccaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccssccccssc88ccc888c000700001caacccaaac7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccsssccsssc88cccc88cc0060001ccaaacaaacc7ccccc7cbbccccccccccc4cccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccsssssscc88cccc88ccc00601ccccaaaaaaac7ccccc7cbbbbbbbbccccc4cccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccssssccc88cccc88cccccccccccccaaacaac7777777ccbbbbbbbccccc4ccccccc77ccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc77777cccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc7777777ccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccc999cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccc99999ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccc99992ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3944423r3r3r3r3r3r3r3r3r3r3r3r333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3944423r3r3r3r3r3r3r3r3r3r3r333r3r333r3r333r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442r3r3r3r3r3r3r3rrr3rrr3rrr3rrr3rrr3rrr3rrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3c44413r3r3r3r3r3r3r333r333r3r333r333r3r333r333r3r333r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rcsss1r3r3r3r3rrr3r3rrr3r3rrr3r3rrr3r3rrr3r3rrr3r3rrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3csss13r3r3r3r333r3r33333r3r333r3r33333r3r333r3r33333r3r333r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rcsss1rrrrr3r3rrrrr3r3rrrrr3r3rrrrr3r3rrrrr3r3rrrrr3r3rrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3csss13r33333r3r33333r3r3r33333r3r33333r3r3r33333r3r33333r3r3r33333r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rcsss1r3r3rrrrr3r3r3rrrrr3r3r3rrrrr3r3r3rrrrr3r3r3rrrrr3r3r3rrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r39sss23r3r3r3333333r3r3r33333r3r3r3333333r3r3r33333r3r3r3333333r3r3r33333r3r3r3r3r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3r3r3r3rrrrrrr3re4442rrrrr3r3r3rrrrrrr3r3r3rrrrrrr3r3r3rrrrrrr3r3r3rrrrrrr3r3r3rrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3r3r3r33333e88823r3333333r3r3r3r3333333r3r3r3333333r3r3r3r3333333r3r3r3333333r3r3r3r3333333r3r3r3r3r3r3r3r3r3
3r3r3r3r3r3r3r3rrrrrrr3r3r3r3re8882r3r3r3r3rrrrrrr3r3r3r3rrrrrrr3r3r3r3rrrrrrr3r3r3r3rrrrrrr3r3r3r3rrrrrrr3r3r3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r3r3333333r3r3e88823333333r3r3r3r3333333r3r3r3r333333333r3r3r3r3333333r3r3r3r333333333r3r3r3r3333333r3r3r3r3r3r3
3r3r3r3rrrrrrrrr3r3r3r3rrrrrrre8882r3r3rrrrrrrrr3r3r3r3rrrrrrrrr3r3r3r3rrrrrrrrr3r3r3r3rrrrrrrrr3r3r3r3rrrrrrrrr3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r333333333r3r3r3r3e8882333r3r3r3r3r333333333r3r3r3r333333333r3r3r3r3r333333333r3r3r3r333333333r3r3r3r3r333333333r3r3
3rrrrrrrrr3r3r3r3r3rrrrrrrrr3r98882r3rrrrrrrrr3r3r3r3r3rrrrrrrrr3r3r3r3r3rrrrrrrrr3r3r3r3r3rrrrrrrrr3r3r3r3r3rrrrrrrrr3r3r3r3r3r
r3r3r3r333333333r3r3r3r3r33333544413r3r3r3r3r333333333r3r3r3r3r33333333333r3r3r3r3r333333333r3r3r3r3r33333333333r3r3r3r3r3333333
3r3r33333333333r3r3r3r3r33333350001r3r3r3r3r33333333333r3r3r3r3r33333333333r3r3r3r3r33333333333r3r3r3r3r33333333333r3r3r3r3r3333
r3r3r3r3r3rrrrrrrrrrrrr3r3r3r350001rrrrrrrr3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3rrrrrrrrrrr3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3rrrrrrrrrrr3
3r3r3r3r3rrrrrrrrrrr3r3r3r3r3r50001rrrrrrr3r3r3r3r3r3rrrrrrrrrrr3r3r3r3r3r3rrrrrrrrrrr3r3r3r3r3r3rrrrrrrrrrr3r3r3r3r3r3rrrrrrrrr
333333r3r3r3r3r3r3333333333333500013r3r3r33333333333r3r3r3r3r3r3333333333333r3r3r3r3r3r33333333333r3r3r3r3r3r3333333333333r3r3r3
33333r3r3r3r3r3r3333333333333r50001r3r3r3333333333333r3r3r3r3r3r3333333333333r3r3r3r3r3r3333333333333r3r3r3r3r3r3333333333333r3r
rrrrrrrrrrrrrrr3r3r3r3r3r3rrrr90002rrrr3r3r3r3r3r3rrrrrrrrrrrrrrr3r3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3r3rrrrrrrrrrrrrrr3r3r3r3r3r3rr
rrrrrrrrrrrr3r3r3r3r3r3r3rrrrr64449rrr3r3r3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3r3r3rrrrrrrrrrrrr3r3r3r3r3r3r
r3r3r3r3r333333333333333r3r3r36aaa93r3333333333333r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r3333333333333r3r3r3r3r3r3r33333333333
3r3r3r3r333333333333333r3r3r3r6aaa9r333333333333333r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r33333333
r3r3r333333333333333r3r3r3r3r36aaa9333333333333333r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r3333333
3r3r333333333333333r3r3r3r3r3r6aaa933333333333333r3r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r3r333333333333333r3r3r3r3r3r3r3r3333
rrr3r3r3r3r3r3r3rrrrrrrrrrrrrr6aaa93r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3
3r3r3r3r3r3r3r3rrrrrrrrrrrrrrr9aaa2r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3rrrrrrrrrrrrrrrr644433r3r3r3r3r3rrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrr
3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr6bbb3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3rrrrrrrrrrrrr
333333333333r3r3r3r3r3r3r3r3r36bbb333333333333r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3r3r3r3r3r33333333333333333r3r3r3r3r3r3
33333333333r3r3r3r3r3r3r3r3r336bbb3333333333333r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3r
33333333r3r3r3r3r3r3r3r3r3r3336bbb333333333333r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3
3333333r3r3r3r3r3r3r3r3r3r33336bbb33333333333r3r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3r
333333r3r3r3r3r3r3r3r3r3r333339bbb2333333333r3r3r3r3r3r3r3r3r3r333333333333333333333r3r3r3r3r3r3r3r3r3r3333333333333333333r3r3r3
3r3rrrrrrrrrrrrrrrrrrrrr3r3r3ra4444r3r3r3r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3rrrrr
r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3a99943r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3rrrr
3rrrrrrrrrrrrrrrrrrrrr3r3r3r3ra9994r3r3r3r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r
rrrrrrrrrrrrrrrrrrrrr3r3r3r3r3a99943r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3
rrrrrrrrrrrrrrrrrrrr3r3r3r3r3ra9994r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r
rrrrrrrrrrrrrrrrrrr3r3r3r3r3r3a99943r3r3rrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3
rrrrrrrrrrrrrrrrrr3r3r3r3r3r3r99992r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r
r3r3r3r3r3r3r3r3r33333333333339444233333r3r3r3r3r3r3r3r3r3r3r3r3333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r33333333333333333
3r3r3r3r3r3r3r3r3333333333333394442333333r3r3r3r3r3r3r3r3r3r3r3r3333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3333333333333333
r3r3r3r3r3r3r3r3333333333333339444233333r3r3r3r3r3r3r3r3r3r3r3r3333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333
3r3r3r3r3r3r3r3333333333333333944423333r3r3r3r3r3r3r3r3r3r3r3r3r3333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r33333333333333
r3r3r3r3r3r3r3333333333333333394442333r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3333333333333
3r3r3r3r3r3r333333333333333333944423333r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r333333333333
r3r3r3r3r3r333333333333333333394442333r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r33333333333
3r3r3r3r3r333333333333333333339444233r3r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r3333333333
r3r3r3r3r333333333333333333333944423r3r3r3r3r3r3r3r3r3r3r3r3r3r33333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r333333333
3r3r3r3r33333333333333333333339444233r3r3r3r3r3r3r3r3r3r3r3r3r3r33333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r33333333
rrrrrrr3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3
rrrrrr3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r
rrrrr3r3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3
rrrr3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r
rrr3r3r3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3
rr3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3r3r3r3r3r3r3r3r394442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3r3r3r3r3r3r3r3rr94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3r3r3r3r3r3r3r3rr94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
3r3r3r3r3r3r3r3r3r3r3r3r3r3rrr94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrrr
r3r3r3r3r3r3r3r3r3r3r3r3r3rrrr94442rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3rrrrrrrrrrrrrrrrrrrrrrrrrrrr
333333333333333333333333333r3r94442r3r3r3r3r3r3r3r3r3r3r3r3r3r3r3333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3r
33333333333333333333333333r3r3944423r3r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3
333333333333333333333333333r3rr434233r3r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r
33333333333333333333333333r3r3rr3r23r3r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r3
3333333333333333333333333r3r353r5r5rr53r3r3r3r3r3r3r3r3r3r3r3r3r333333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3r
333333333333333333333333r3r3r535535r3rr3r3r3r3r3r3r3r3r3r3r3r3r33333333333333333333333333333333333333333r3r3r3r3r3r3r3r3r3r3r3r3

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
49090000183201f320243200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060000183201f32024320283202b320303203032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
