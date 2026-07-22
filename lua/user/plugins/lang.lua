local markview_filetypes = {
	markdown = true,
	quarto = true,
	rmd = true,
	typst = true,
	tex = true,
	plaintex = true,
	latex = true,
}

local toolchain = require("user.toolchain")

local function refresh_markview(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not markview_filetypes[vim.bo[bufnr].filetype] then
		return
	end

	vim.defer_fn(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local ok_state, state = pcall(require, "markview.state")
		if not ok_state or not state.enabled() or not state.buf_attached(bufnr) then
			return
		end

		local buf_state = state.get_buffer_state(bufnr, false)
		if not buf_state or not buf_state.enable then
			return
		end

		local ok_actions, actions = pcall(require, "markview.actions")
		if ok_actions then
			pcall(actions.render, bufnr)
		end
	end, 20)
end

return {
	{
		"mrcjkb/rustaceanvim",
		ft = { "rust" },
		init = function()
			-- rustaceanvim manages rust_analyzer + DAP (codelldb) + neotest itself.
			-- Settings migrated from the former manual rust_analyzer lsp config.
			vim.g.rustaceanvim = {
				server = {
					cmd = { toolchain.executable("rust-analyzer") or "rust-analyzer" },
					on_attach = function(_, bufnr)
						local function debug_continue()
							if not toolchain.executable("codelldb") then
								vim.notify(
									"Rust debugging requires codelldb; run :MasonToolsInstall",
									vim.log.levels.ERROR,
									{ title = "Rust" }
								)
								return
							end
							require("lazy").load({ plugins = { "nvim-dap" } })
							local dap = require("dap")
							if dap.session() or #(dap.configurations.rust or {}) > 0 then
								dap.continue()
							else
								vim.cmd("RustLsp debuggables")
							end
						end
						vim.keymap.set("n", "<F5>", debug_continue, {
							buffer = bufnr,
							desc = "Debug Rust: continue / select",
						})
						vim.keymap.set("n", "<leader>dc", debug_continue, {
							buffer = bufnr,
							desc = "Debug Rust: continue / select",
						})
					end,
					default_settings = {
						["rust-analyzer"] = {
							cargo = { allFeatures = true },
							check = { command = "clippy" },
						},
					},
				},
				dap = {
					autoload_configurations = false,
					adapter = function()
						local command = toolchain.executable("codelldb")
						if not command then
							return false
						end
						return {
							type = "server",
							host = "127.0.0.1",
							port = "${port}",
							executable = {
								command = command,
								args = { "--port", "${port}" },
							},
						}
					end,
				},
			}
		end,
	},
	{
		"saecki/crates.nvim",
		tag = "stable",
		event = { "BufRead Cargo.toml", "BufNewFile Cargo.toml" },
		opts = {
			completion = {
				crates = { enabled = true },
			},
			-- Expose crates as a fake LSP so blink.cmp picks up version/feature
			-- completion, hover docs, and code actions through the existing "lsp"
			-- source -- no blink.compat shim needed.
			lsp = {
				enabled = true,
				actions = true,
				completion = true,
				hover = true,
			},
		},
		config = function(_, opts)
			local crates = require("crates")
			crates.setup(opts)

			local function is_cargo_toml(bufnr)
				return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") == "Cargo.toml"
			end

			local function map_crates_keys(bufnr)
				if not is_cargo_toml(bufnr) then
					return
				end

				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				-- localleader: buffer-local crate actions must not shadow the global
				-- <leader>c code maps (<leader>cf Format, <leader>cd diagnostics, ...).
				map("<localleader>t", crates.toggle, "Crates toggle")
				map("<localleader>v", crates.show_versions_popup, "Crate versions")
				map("<localleader>f", crates.show_features_popup, "Crate features")
				map("<localleader>d", crates.show_dependencies_popup, "Crate dependencies")
				map("<localleader>u", crates.update_crate, "Crate update")
				map("<localleader>U", crates.upgrade_crate, "Crate upgrade")
				map("<localleader>A", crates.upgrade_all_crates, "Crates upgrade all")
			end

			vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
				group = vim.api.nvim_create_augroup("user_crates_keys", { clear = true }),
				pattern = "Cargo.toml",
				callback = function(event)
					if event.event == "BufNewFile" then
						-- crates.nvim's own autoload callback currently listens only
						-- to BufRead. Replay that callback group for new files so every
						-- Cargo.toml gets its cache, fake LSP, and completion support.
						vim.api.nvim_exec_autocmds("BufRead", {
							group = "Crates",
							buffer = event.buf,
						})
					end
					map_crates_keys(event.buf)
				end,
			})

			-- The event that loaded the plugin has already fired before config runs.
			map_crates_keys(vim.api.nvim_get_current_buf())
		end,
	},
	{
		"OXY2DEV/markview.nvim",
		ft = { "markdown", "quarto", "rmd", "typst", "tex", "plaintex", "latex" },
		dependencies = { "saghen/blink.cmp" },
		opts = {
			preview = {
				filetypes = { "markdown", "quarto", "rmd", "typst", "tex", "plaintex", "latex" },
				icon_provider = "mini",
			},
		},
		config = function(_, opts)
			require("markview").setup(opts)

			vim.api.nvim_create_autocmd("InsertLeave", {
				group = vim.api.nvim_create_augroup("user_markview_refresh", { clear = true }),
				pattern = "*",
				callback = function(event)
					refresh_markview(event.buf)
				end,
			})
		end,
		keys = {
			{ "<leader>mp", "<cmd>Markview Toggle<cr>", desc = "Markup preview" },
			{ "<leader>ms", "<cmd>Markview splitToggle<cr>", desc = "Markup split preview" },
			{ "<leader>mh", "<cmd>Markview HybridToggle<cr>", desc = "Markup hybrid mode" },
		},
	},
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
		ft = { "markdown" },
		-- Use the plugin's prebuilt installer; this avoids making Yarn an
		-- undocumented deployment requirement.
		build = function()
			vim.fn["mkdp#util#install_sync"]()
			if vim.trim(vim.fn["mkdp#util#pre_build_version"]()) == "" then
				error("markdown-preview.nvim prebuilt binary installation failed")
			end
		end,
		init = function()
			vim.g.mkdp_auto_start = 0
			vim.g.mkdp_auto_close = 1
			vim.g.mkdp_refresh_slow = 0
			vim.g.mkdp_command_for_global = 0
			vim.g.mkdp_open_to_the_world = 0
			vim.g.mkdp_open_ip = "127.0.0.1"
			vim.g.mkdp_browser = ""
			vim.g.mkdp_echo_preview_url = 1
			vim.g.mkdp_page_title = "${name}"
			vim.g.mkdp_filetypes = { "markdown" }
			vim.g.mkdp_theme = "dark"
			vim.g.mkdp_preview_options = {
				sync_scroll_type = "middle",
				hide_yaml_meta = 1,
			}
		end,
		config = function()
			local function map_markdown_keys(bufnr)
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				map("<leader>mv", "<cmd>MarkdownPreviewToggle<cr>", "Markdown preview")
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_markdown_keys", { clear = true }),
				pattern = "markdown",
				callback = function(event)
					map_markdown_keys(event.buf)
				end,
			})

			map_markdown_keys(vim.api.nvim_get_current_buf())
		end,
	},
	{
		"lervag/vimtex",
		ft = { "tex", "plaintex", "bib" },
		init = function()
			vim.g.vimtex_compiler_method = "latexmk"
			vim.g.vimtex_compiler_latexmk = {
				callback = 1,
				continuous = 1,
				executable = "latexmk",
				options = {
					"-interaction=nonstopmode",
					"-synctex=1",
					"-file-line-error",
				},
			}
			if vim.fn.executable("zathura") == 1 then
				vim.g.vimtex_view_method = "zathura"
			elseif vim.fn.has("macunix") == 1 then
				vim.g.vimtex_view_method = "skim"
			end
			vim.g.vimtex_view_forward_search_on_start = 1
			vim.g.vimtex_quickfix_mode = 0
			vim.g.vimtex_quickfix_open_on_warning = 0
		end,
		config = function()
			local function map_tex_keys(bufnr)
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				map("<leader>mc", "<cmd>VimtexCompile<cr>", "LaTeX compile")
				map("<leader>mv", "<cmd>VimtexView<cr>", "LaTeX preview")
				map("<leader>mt", "<cmd>VimtexTocToggle<cr>", "LaTeX table of contents")
				map("<leader>me", "<cmd>VimtexErrors<cr>", "LaTeX errors")
				map("<leader>mk", "<cmd>VimtexStop<cr>", "LaTeX stop compiler")
				map("<leader>mx", "<cmd>VimtexClean<cr>", "LaTeX clean aux files")
				map("<leader>mi", "<cmd>VimtexInfo<cr>", "LaTeX info")
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_vimtex_keys", { clear = true }),
				pattern = { "tex", "plaintex", "bib" },
				callback = function(event)
					map_tex_keys(event.buf)
				end,
			})

			map_tex_keys(vim.api.nvim_get_current_buf())
		end,
	},
	{
		"brianhuster/live-preview.nvim",
		cmd = "LivePreview",
		ft = "html",
		opts = {},
		config = function(_, opts)
			require("livepreview").setup(opts)

			local function map_html_keys(bufnr)
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				map("<leader>mv", "<cmd>LivePreview start<cr>", "HTML preview")
				map("<leader>mk", "<cmd>LivePreview close<cr>", "HTML stop preview")
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_live_preview_keys", { clear = true }),
				pattern = "html",
				callback = function(event)
					map_html_keys(event.buf)
				end,
			})

			map_html_keys(vim.api.nvim_get_current_buf())
		end,
	},
	{
		"chomosuke/typst-preview.nvim",
		ft = "typst",
		version = "1.*",
		opts = {
			dependencies_bin = {
				tinymist = toolchain.executable("tinymist") or "tinymist",
			},
			follow_cursor = true,
		},
		config = function(_, opts)
			require("typst-preview").setup(opts)

			local function map_typst_keys(bufnr)
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				map("<leader>mc", "<cmd>TypstCompilePdf<cr>", "Typst compile")
				map("<leader>mv", "<cmd>TypstPreviewToggle<cr>", "Typst preview")
				map("<leader>mk", "<cmd>TypstPreviewStop<cr>", "Typst stop preview")
				map("<leader>mf", "<cmd>TypstPreviewFollowCursorToggle<cr>", "Typst follow cursor")
				map("<leader>my", "<cmd>TypstPreviewSyncCursor<cr>", "Typst sync cursor")
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_typst_preview_keys", { clear = true }),
				pattern = "typst",
				callback = function(event)
					map_typst_keys(event.buf)
				end,
			})

			map_typst_keys(vim.api.nvim_get_current_buf())
		end,
	},
}
