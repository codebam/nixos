require("blink.cmp").setup({
	signature = { enabled = true },
	snippets = { preset = "luasnip" },
	ghost_text = {
		enabled = true,
	},
	documentation = {
		auto_show = true,
		auto_show_delay_ms = 0,
	},
	accept = {
		auto_brackets = {
			enabled = true,
			blocked_filetypes = { "gleam" },
		},
	},
	sources = {
		transform_items = function(_, items)
			for _, item in ipairs(items) do
				if item.kind == require("blink.cmp.types").CompletionItemKind.Snippet then
					item.score_offset = item.score_offset + 10
				end
			end
			return items
		end,
		default = {
			"snippets",
			"lsp",
			"copilot",
			"path",
			"lazydev",
			"omni",
		},
		providers = {
			lazydev = {
				name = "LazyDev",
				module = "lazydev.integrations.blink",
				score_offset = 100,
			},
			copilot = {
				name = "copilot",
				module = "blink-cmp-copilot",
				score_offset = 100,
				async = true,
			},
		},
	},
})

require("lualine").setup()

require("nvim-treesitter.configs").setup({
	auto_install = false,
	ignore_install = {},
	highlight = {
		enable = true,
		additional_vim_regex_highlighting = false,
	},
	indent = {
		enable = true,
	},
	incremental_selection = {
		enable = true,
		keymaps = {
			init_selection = "<C-space>",
			node_incremental = "<C-space>",
			scope_incremental = false,
			node_decremental = "<bs>",
		},
	},
	textobjects = {
		select = {
			enable = true,
			lookahead = true,

			keymaps = {
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",

				["as"] = "@statement.outer",
				["is"] = "@statement.inner",

				["al"] = "@loop.outer",
				["il"] = "@loop.inner",

				["aa"] = "@parameter.outer",
				["ia"] = "@parameter.inner",

				["a="] = "@assignment.outer",
				["i="] = "@assignment.inner",
				["alhs"] = "@assignment.lhs",
				["arhs"] = "@assignment.rhs",
			},
			include_surrounding_whitespace = true,
		},

		move = {
			enable = true,
			set_jumps = true,
			goto_next_start = {
				["]f"] = "@function.outer",
				["]c"] = "@class.outer",
				["]a"] = "@parameter.inner",
				["]s"] = "@statement.outer",
			},
			goto_next_end = {
				["]F"] = "@function.outer",
				["]C"] = "@class.outer",
				["]A"] = "@parameter.inner",
				["]S"] = "@statement.outer",
			},
			goto_previous_start = {
				["[f"] = "@function.outer",
				["[c"] = "@class.outer",
				["[a"] = "@parameter.inner",
				["[s"] = "@statement.outer",
			},
			goto_previous_end = {
				["[F"] = "@function.outer",
				["[C"] = "@class.outer",
				["[A"] = "@parameter.inner",
				["[S"] = "@statement.outer",
			},
			goto_next_start = {
				["]m"] = "@comment.outer",
			},
		},

		swap = {
			enable = true,
			swap_next = {
				["<leader>na"] = "@parameter.inner",
				["<leader>nf"] = "@function.outer",
			},
			swap_previous = {
				["<leader>pa"] = "@parameter.inner",
				["<leader>pf"] = "@function.outer",
			},
		},
		lsp_interop = {
			enable = true,
			peek_definition_code = {
				["<leader>df"] = "@function.outer",
				["<leader>dF"] = "@class.outer",
			},
		},
	},
})

require("conform").setup({
	formatters_by_ft = {
		lua = { "stylua" },
		python = { "isort", "black" },
		rust = { "rustfmt", lsp_format = "fallback" },
		javascript = { "prettierd", "prettier", stop_after_first = true },
		typescript = { "prettierd", "prettier", stop_after_first = true },
	},
	format_on_save = {
		timeout_ms = 500,
		lsp_format = "fallback",
	},
})

require("oil").setup()

require("nvim-autopairs").setup()

require("gitsigns").setup()

require("neogit").setup()

require("copilot").setup({
	suggestion = {
		enabled = false,
	},
	panel = {
		enabled = false,
	},
})
vim.api.nvim_create_autocmd("User", {
	pattern = "BlinkCmpMenuOpen",
	callback = function()
		vim.b.copilot_suggestion_hidden = true
	end,
})
vim.api.nvim_create_autocmd("User", {
	pattern = "BlinkCmpMenuClose",
	callback = function()
		vim.b.copilot_suggestion_hidden = false
	end,
})

require("avante").setup({
	provider = "copilot",
	providers = {
		ollama = {
			model = "devstral",
		},
		gemini = {
			model = "gemini-2.5-flash-preview-05-20",
		},
	},
	behaviour = {
		auto_approve_tool_permissions = true,
	},
})
