pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- pico-8 game: jira sprint manager

-- constants
local sprint_capacity = 20
local max_tasks = 15
local bucket_speed = 2
local fall_speed = 1
local bug_pause_time = 60 -- time to pause when a bug is found
local game_over_time = 120 -- time to show "game over" screen (2 seconds at 30 fps)
local drop_interval = 30 -- frames between drops
local capacity_increase_probability = 0.5 -- 50% chance
local high_sp_threshold = 6 -- consider high sp as 6 or more
local min_unplanned_work = 2
local max_unplanned_work = 10
local unplanned_work_sprite_index = 1 -- set the sprite index for unplanned work

-- colors
local jira_blue = 12
local white = 7
local red = 8
local high_priority = 9 -- yellow
local medium_priority = 10 -- orange
local low_priority = 11 -- green
local green = 11

-- game state
backlog = {}
falling_tasks = {}
unplanned_tasks = {}
bucket = {x = 64, y = 120, width = 16, height = 8, sprite_index = 0}
burndown = 0
capacity = sprint_capacity
game_over = false
sprint_number = 1
bug_found = false
bug_timer = 0
game_over_timer = 0
drop_timer = 0
wip_admonished = false
capacity_increase_message = false
capacity_increase_timer = 0

-- splash screen state
show_splash = true
splash_timer = 0

-- task generation
function generate_task()
    local priority = flr(rnd(3)) + 1 -- random priority between 1 and 3
    local priority_color
    if priority == 1 then
        priority_color = low_priority
    elseif priority == 2 then
        priority_color = medium_priority
    else
        priority_color = high_priority
    end
    local task = {
        title = "task "..tostr(#backlog + 1),
        story_points = flr(rnd(8)) + 1, -- random story points between 1 and 8
        bug_probability = 0.5, -- 50% bug probability
        x = rnd(120), -- random x position
        y = -8, -- start above the screen
        priority = priority,
        priority_color = priority_color,
        unplanned = false
    }
    return task
end

function generate_unplanned_task()
    local task = {
        title = "unplanned "..tostr(#unplanned_tasks + 1),
        story_points = flr(rnd(2)) + 1, -- low story points (1-2 sp)
        actual_multiplier = flr(rnd(4)) + 2, -- actual points between 2x and 5x
        x = rnd(120), -- random x position
        y = -8, -- start above the screen
        priority = 1, -- low priority
        priority_color = low_priority,
        unplanned = true,
        sprite_index = unplanned_work_sprite_index -- set the sprite index for unplanned work
    }
    return task
end

-- initialize backlog
function init_backlog()
    backlog = {}
    for i = 1, max_tasks do
        add(backlog, generate_task())
    end
    init_unplanned_work()
end

-- initialize unplanned work
function init_unplanned_work()
    unplanned_tasks = {}
    local num_unplanned = flr(rnd(max_unplanned_work - min_unplanned_work + 1)) + min_unplanned_work
    for i = 1, num_unplanned do
        add(unplanned_tasks, generate_unplanned_task())
    end
end

-- add falling task
function add_falling_task()
    if #unplanned_tasks > 0 and rnd(1) < 0.3 then -- 30% chance to drop unplanned work
        local task = deli(unplanned_tasks, 1)
        add(falling_tasks, task)
    elseif #backlog > 0 then
        local task = deli(backlog, 1)
        add(falling_tasks, task)
    end
end

-- move bucket
function move_bucket()
    if btn(0) then
        bucket.x -= bucket_speed
    end
    if btn(1) then
        bucket.x += bucket_speed
    end
    -- keep bucket within screen bounds
    bucket.x = mid(0, bucket.x, 128 - bucket.width)
end

-- find index of a task in a list
function indexof(list, item)
    for i = 1, #list do
        if list[i] == item then
            return i
        end
    end
    return nil
end

-- update falling tasks
function update_falling_tasks()
    drop_timer += 1
    if drop_timer > drop_interval then
        add_falling_task()
        drop_timer = 0
    end

    for task in all(falling_tasks) do
        task.y += fall_speed
        -- check if task is caught by the bucket
        if task.y >= bucket.y and task.y <= bucket.y + bucket.height and task.x >= bucket.x and task.x <= bucket.x + bucket.width then
            -- calculate actual story points (considering bugs)
            local actual_points = task.story_points
            if task.unplanned then
                actual_points *= task.actual_multiplier -- multiply for unplanned work
            elseif rnd(1) < task.bug_probability then
                actual_points *= 2 -- double points if it has bugs
                bug_found = true
                bug_timer = bug_pause_time
                sfx(2) -- buzzer sound
                -- check for capacity increase
                if (task.priority == 3 or task.story_points >= high_sp_threshold) and rnd(1) < capacity_increase_probability then
                    capacity += 2
                    capacity_increase_message = true
                    capacity_increase_timer = 60 -- show message for 1 second
                    sfx(3) -- capacity increase sound
                end
            else
                sfx(0) -- happy fanfare for catching a card
            end
            burndown += actual_points
            capacity -= task.story_points
            deli(falling_tasks, indexof(falling_tasks, task))
        elseif task.y > 128 then
            -- remove task if it falls off the screen
            deli(falling_tasks, indexof(falling_tasks, task))
        end
    end
end

-- draw splash screen
function draw_splash()
    cls()
    local base_y = 64
    local t = splash_timer / 30
    local text = "scrumaster"
    local text_length = #text * 8
    local start_x = (128 - text_length) / 2
    for i = 1, #text do
        local char = sub(text, i, i)
        local y = base_y + 10 * sin(t + i / 6.5)
        print(char, start_x + (i - 1) * 8, y, jira_blue)
    end
    print("press x to start", 30, 90, white)
end

-- draw ui
function draw_ui()
    cls()
    -- draw backlog
    print("backlog", 2, 2, jira_blue)
    for i = 1, #backlog do
        local task = backlog[i]
        print(task.title .. " (" .. task.story_points .. " sp)", 2, 10 + i * 8, jira_blue)
    end

    -- draw burndown and capacity
    print("burndown: " .. burndown, 2, 100, white)
    print("capacity: " .. capacity, 2, 110, white)
    print("sprint: " .. sprint_number, 2, 120, white)

    -- draw bucket
    spr(bucket.sprite_index, bucket.x, bucket.y)

    -- draw falling tasks
    for task in all(falling_tasks) do
        if task.unplanned then
            spr(task.sprite_index, task.x, task.y) -- use the specified sprite index for unplanned work
        else
            rectfill(task.x, task.y, task.x + 8, task.y + 8, jira_blue)
        end
        print(task.story_points .. " sp", task.x, task.y + 2, white)
        pset(task.x + 4, task.y + 4, task.priority_color) -- draw priority indicator
    end

    -- draw bug message if a bug is found
    if bug_found then
        print("bug found!", 50, 30, red)
    end

    -- draw capacity increase message
    if capacity_increase_message then
        print("+2 capacity", 50, 50, green)
    end
end

-- draw game over message
function draw_game_over()
    print("game over!", 50, 64, white)
    if wip_admonished then
        print("limit your wip!", 40, 80, red)
    end
end

-- main update loop
function _update()
    if show_splash then
        splash_timer += 1
        if splash_timer == 1 then
            music(0) -- start the intro music
        end
        if btnp(5) then -- 'x' to start the game
            music(-1) -- stop the intro music
            show_splash = false
            init_backlog()
        end
    else
        if game_over then
            game_over_timer += 1
            if game_over_timer > game_over_time then
                show_splash = true
                game_over = false
                game_over_timer = 0
                wip_admonished = false
                sprint_number = 1
                burndown = 0
                capacity = sprint_capacity
                backlog = {}
                falling_tasks = {}
                unplanned_tasks = {}
            end
        else
            if bug_found then
                bug_timer -= 1
                if bug_timer <= 0 then
                    bug_found = false
                end
            else
                move_bucket()
                update_falling_tasks()
                if #falling_tasks < 3 and (#backlog > 0 or #unplanned_tasks > 0) then
                    add_falling_task()
                end
                if capacity <= 0 then
                    game_over = true
                elseif #backlog == 0 and #falling_tasks == 0 and #unplanned_tasks == 0 then
                    if sprint_number == 1 and burndown < sprint_capacity then
                        wip_admonished = true
                    end
                    sprint_number += 1
                    capacity = sprint_capacity
                    -- carry over remaining tasks
                    for task in all(falling_tasks) do
                        add(backlog, task)
                    end
                    falling_tasks = {}
                    unplanned_tasks = {}
                    -- initialize new tasks for the new sprint
                    init_backlog()
                    burndown = 0
                    sfx(1) -- happy fanfare for completing a sprint
                end
            end
        end
    end

    -- update capacity increase message timer
    if capacity_increase_message then
        capacity_increase_timer -= 1
        if capacity_increase_timer <= 0 then
            capacity_increase_message = false
        end
    end
end

-- main draw loop
function _draw()
    if show_splash then
        draw_splash()
    else
        draw_ui()
        if game_over then
            draw_game_over()
        end
    end
end

-- sound effects
-- sfx 0: happy fanfare for catching a card
-- sfx 1: happy fanfare for completing a sprint
-- sfx 2: buzzer sound for finding a bug
-- sfx 3: capacity increase sound

-- music
-- music 0: intro music

-- initialize game
init_backlog()

__gfx__
0001c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c1cc00007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cc11cc0c272a72c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cc1001ccc2ca2c2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cc1001ccc2c2ac2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cc11cc0c2ca777c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00cc1c00c2c277770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c1000c2ca777c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c0c0000cc00cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c0c0c0c0c000c0c0c000c0c0c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00cc00ccc0c000cc00c000c0c0c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c0c0c0c0c000c0c0c000c0c0c0c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0c0c00cc0c0c0ccc0cc00ccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccc0000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccc0000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000077ccccccc7707770000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c7cccccc70007070000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c7cc9ccc77707770000000000
00ccc0ccc00cc0c0c00000ccc000000c00c0c000000cc0ccc00c000000000000000000000000000000000000000000000000000c7ccccccc0707000000000000
000c00c0c0c000c0c00000c0000000c000c0c00000c000c0c000c00000000000000000000000000000000000000000000000000777ccccc77007000000000000
000c00ccc0ccc0cc000000ccc00000c000ccc00000ccc0ccc000c00000000000000000000000000000000000000000000000000ccccccccc0000000000000000
000c00c0c000c0c0c0000000c00000c00000c0000000c0c00000c00000000000000000000000000000000000000000000000000ccccccccc0000000000000000
000c00c0c0cc00c0c00000ccc000000c0000c00000cc00c0000c0000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000c00000000c00ccc000000cc0ccc00c0000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c00000c0000000c00000c00000c000c0c000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc000000ccc00000c00000c00000ccc0ccc000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c00000c0c00000c00000c0000000c0c00000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c00000ccc000000c0000c00000cc00c0000c0000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000ccc000000c00ccc000000cc0ccc00c0000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c0000000c00000c00000c00000c000c0c000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc00000000c00000c0000cc00000ccc0ccc000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c0000000c00000c00000c0000000c0c00000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c0000000c000000c00ccc00000cc00c0000c0000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000ccc000000c00c0c000000cc0ccc00c0000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c00000c0c00000c000c0c00000c000c0c000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c0ccccccccccc000000ccc00000c000ccc00000ccc0ccc000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c0cccccccccc0c00000c0c00000c00000c0000000c0c00000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c0777cccccc77c77700ccc000000c0000c00000cc00c0000c0000000000000000000000000000000000000000000000000000000000000000000000000000
00000cc7ccccc7000707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000c77cbccc7770777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000cc7cccccc070700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc777ccccc770c70000ccc000000c00c0c000000cc0ccc00c0000000000000000000000000000000000000000000000000000000000000000000000000000
000c0cccccccccc0c00000c0c00000c000c0c00000c000c0c000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c0ccccccccccc000000ccc00000c000ccc00000ccc0ccc000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c0000000c00000c00000c0000000c0c00000c000000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c0000000c000000c0000c00000cc00c0000c0000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000cc00ccc000000c00ccc000000cc0ccc00c000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c000000c00c0c00000c00000c00000c000c0c000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc0000000c00c0c00000c0000cc00000ccc0ccc000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c000000c00c0c00000c00000c0000000c0c00000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c00000ccc0ccc000000c00ccc00000cc00c0000c000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000cc00cc0000000c00ccc000000cc0ccc00c000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c000000c000c000000c00000c00000c000c0c000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc0000000c000c000000c0000cc00000ccc0ccc000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c000000c000c000000c00000c0000000c0c00000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c00000ccc0ccc000000c00ccc00000cc00c0000c000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000ccccccccc00000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000ccccccccc00000000000000000000000000000000000000000000000000000
00000777700000000000000000000000000000000000000000000000000000000077ccccccc7707770000000000000000000000ccccccccc0000000000000000
00c7772a72cc77c7770000cc00ccc000000c00ccc000000cc0ccc00c0000000000c7cccccc70007070000000000000000000000ccccccccc0000000000000000
000c27a2c2c700c7c700000c0000c00000c00000c00000c000c0c000c000000000c7ccbccc7770777000000000000000000000077ccccccc7707770000000000
0007772bc2c777c77700000c00ccc00000c0000cc00000ccc0ccc000c000000000c7ccccccc0707000000000000000000000000c7cccccc70007070000000000
00072ca777c0c7c7c000000c00c0000000c00000c0000000c0c00000c000000000777ccccc77007000000000000000000000000c7cc9ccc77707770000000000
00077727777770c7c00000ccc0ccc000000c00ccc00000cc00c0000c0000000000ccccccccc0000000000000000000000000000c7ccccccc0707000000000000
000c2ca777c0000000000000000000000000000000000000000000000000000000ccccccccc0000000000000000000000000000777ccccc77007000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccc0000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccc0000000000000000
00ccc0ccc00cc0c0c00000cc00ccc000000c00ccc000000cc0ccc00c000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c000000c0000c00000c00000c00000c000c0c000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc0000000c000cc00000c00000c00000ccc0ccc000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c000000c0000c00000c00000c0000000c0c00000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c00000ccc0ccc000000c0000c00000cc00c0000c000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000cc00c0c000000c00ccc000000cc0ccc00c000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c000000c00c0c00000c00000c00000c000c0c000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00ccc0ccc0cc0000000c00ccc00000c0000cc00000ccc0ccc000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c000c0c0c000000c0000c00000c00000c0000000c0c00000c00000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0cc00c0c00000ccc000c000000c00ccc00000cc00c0000c000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccc0ccc00cc0c0c00000cc00ccc000000c00ccc000000cc0ccc00c000000000000000000000000000000000000000000000000000000000000000000000000
000c00c0c0c000c0c000000c00c0000000c00000c00000c000c0c000c00000000000000000000000000000000000000000000000000000000000000000000000
0077707c7077707700770007707c707700c0000cc07770ccc0ccc000c00000000000000000000000000000000000000000000000000000000000000000000000
007c7070707070707070707c7070707070c70000c0707000c0c00000c00000000000000000000000000000000000000000000000000000000000000000000000
00770070707700707070707c707c7070700c00ccc07070cc00c0000c000000000000000000000000000000000000000000000000000000000000000000000000
00707070707070707070707070777070700700000070700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777007707070707077707700777070700000000077700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077077707770777007707770777070700000000077707770000000000000000000000000000000000000000000000000000000000000000000000000000000
00700070707070707070000700070070700700000000707070000000000000000000000000000000000000000000000000000000000000000000000000000000
00700077707770777070000700070077700000000077707070000000000000000000000000000000000000000000000000000000000000000000000000000000
00700070707000707070000700070000700700000070007070000000000000000000000000000000000000000000000000000000000000000000000000000000
00077070707000707007707770070077700000000077707770000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077077707770777077007770000000007700000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000
007000707070700700707007000700000007000000000000000000000000000000000000000000c1cc0000000000000000000000000000000000000000000000
00777077707700070070700700000000000700000000000000000000000000000000000000000cc11cc000000000000000000000000000000000000000000000
0000707000707007007070070007000000070000000000000000000000000000000000000000cc1001cc00000000000000000000000000000000000000000000
0077007000707077707070070000000000777000000000000000000000000000000000000000cc1001cc00000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000cc11cc000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000cc1c0000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000c100000000000000000000000000000000000000000000000

__sfx__
7d043f021b0501b05022050220501b05016800168000f8000f8000f8000f800168001680016800168000f8000f8000f80016800168001680016800168000d8000d8000d800168000f8000f800168000f8000f800
3018a100000000001002010020100201002010000000000000000000000000000000000000000000000000000000000000000000000000000008773eb773eb773eb773eb773eb773eb7700000000000001002020
310f00001e0502005022050220501e050200500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000f0201b020140201d0201d0200e0200f8000f8000f8000f800168001680016800168000f8000f8000f80016800168001680016800168000d8000d8000d800168000f8000f800168000f8000f80000000
0110000022020200201e0201e020220201e0200000000000000000000036a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
151000000e03011030100300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
302000000d95000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
02 01020304
00 01020304
00 01020304
00 01020304
02 01020304
