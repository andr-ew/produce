local Produce = {
    grid = {},
    enc = {},
    key = {},
    screen = {},
    arc = {}
}

do
    local default_args = {
        blink_time = 0.25,
    }
    default_args.__index = default_args

    local default_props = {
        x = 1,                           --x position of the component
        y = 1,                           --y position of the component
        varibright = true,
        events = {
            pre_clear = function() end,
            post_stop = function() end,
            pre_resume = function() end,
            pre_rec_stop = function() end,
            post_rec_start = function() end,
        }
    }
    default_props.__index = default_props

    function Produce.grid.pattern_recorder(args)
        args = args or {}
        setmetatable(args, default_args)

        local downtime = 0
        local lasttime = 0

        local blinking = false
        local blink = 0

        clock.run(function()
            while true do
                if blinking then
                    blink = 1
                    crops.dirty.grid = true
                    clock.sleep(args.blink_time)

                    blink = 0
                    crops.dirty.grid = true
                    clock.sleep(args.blink_time)
                else
                    blink = 0
                    clock.sleep(args.blink_time)
                end
            end
        end)

        return function(props)
            if crops.device == 'grid' then
                setmetatable(props, default_props)
                if rawget(props, 'events') then
                    setmetatable(props.events, default_props.events)
                end

                local pattern = props.pattern

                if crops.mode == 'input' then
                    local x, y, z = table.unpack(crops.args)

                    if x == props.x and y == props.y then
                        if z==1 then
                            downtime = util.time()
                        else
                            local theld = util.time() - downtime
                            local tlast = util.time() - lasttime
                            
                            if theld > 0.5 then --hold to clear
                                pattern:stop()
                                props.events.pre_clear()
                                pattern:clear()
                                blinking = false
                            else
                                if pattern.data.count > 0 then
                                    if tlast < 0.3 then --double-tap to overdub
                                        pattern:resume()
                                        pattern:set_overdub(1)
                                        props.events.post_rec_start()
                                        blinking = true
                                    else
                                        if pattern.rec == 1 then --play pattern / stop inital recording
                                            props.events.pre_rec_stop()
                                            pattern:rec_stop()
                                            pattern:start()
                                            blinking = false
                                        elseif pattern.overdub == 1 then --stop overdub
                                            props.events.pre_rec_stop()
                                            pattern:set_overdub(0)
                                            blinking = false
                                        else
                                            if pattern.play == 0 then --resume pattern
                                                props.events.pre_resume()
                                                pattern:resume()
                                                blinking = false
                                            elseif pattern.play == 1 then --pause pattern
                                                pattern:stop() 
                                                props.events.post_stop()
                                                blinking = false
                                            end
                                        end
                                    end
                                else
                                    if pattern.rec == 0 then --begin initial recording
                                        pattern:rec_start()
                                        props.events.post_rec_start()
                                        blinking = true
                                    else
                                        pattern:rec_stop()
                                        blinking = false
                                    end
                                end
                            end

                            crops.dirty.grid = true
                            lasttime = util.time()
                        end
                    end
                elseif crops.mode == 'redraw' then
                    local g = crops.handler

                    local lvl
                    do
                        local off = 0
                        local dim = (props.varibright == false) and 0 or 4
                        local med = (props.varibright == false) and 15 or 4
                        -- local medhi = (props.varibright == false) and 15 or 8 
                        local hi = 15

                        local empty = 0
                        -- local armed = ({ off, med })[blink + 1]
                        local armed = med
                        local recording = ({ off, med })[blink + 1]
                        local playing = hi
                        local paused = dim
                        local overdubbing = ({ dim, hi })[blink + 1]

                        lvl = (
                            pattern.rec==1 and (pattern.data.count>0 and recording or armed)
                            or (
                                pattern.data.count>0 and (
                                    pattern.overdub==1 and overdubbing
                                    or pattern.play==1 and playing
                                    or paused
                                ) or empty
                            )
                        )
                    end

                    if lvl>0 then g:led(props.x, props.y, lvl) end
                end
            end
        end
    end
end

return Produce
