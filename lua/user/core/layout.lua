return {
	-- Shared by lazygit, the floating terminal, and the scratch buffer. 0.9 is fine
	-- now that lazygit is nudged up a row (see git.lua) so its bottom border clears
	-- the global statusline (laststatus=3); the terminal already self-corrects.
	float_scale = 0.9,
}
