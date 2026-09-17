-- Automatic pair hints can yield to waiting input. The next idle timer
-- recomputes the full result with the plugin's original search budget.
return function(state, timer_name)
	local api = vim.api
	local pending = {}
	return function()
		if not state.active or vim.fn.getchar(1) == 0 then
			return false
		end
		local stack = vim.fn.expand("<stack>")
		if not stack:find(timer_name, 1, true) and not stack:find("matchup#matchparen#scroll_callback", 1, true) then
			return false
		end
		local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
		if not pending[win] then
			vim.fn["matchup#perf#timeout_start"](1)
			state.interruptions = state.interruptions + 1
			pending[win] = true
			vim.schedule(function()
				pending[win] = nil
				if not state.active or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then
					return
				end
				api.nvim_win_call(win, function()
					local timer = vim.w.matchup_timer
					if timer and #vim.fn.timer_info(timer) > 0 then
						-- The aborted search stored this cursor before computing.
						-- Make the normal idle callback recompute it even when a
						-- wheel event moves only the viewport, not the cursor.
						vim.w.last_cursor = nil
						vim.w.matchup_pulse_time = vim.fn.reltime()
						vim.fn.timer_pause(timer, 0)
						state.resumes = state.resumes + 1
					end
				end)
			end)
		end
		return true
	end
end
