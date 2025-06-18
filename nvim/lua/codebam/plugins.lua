require("blink.cmp").setup({
	signature = { enabled = true },
	snippets = { preset = "luasnip" },
	keymap = {
		preset = "enter",
		["<Tab>"] = { "snippet_forward", "select_next", "fallback" },
		["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
	},
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
			"lsp",
			"path",
			"snippets",
			"lazydev",
			"omni",
		},
		providers = {
			lazydev = {
				name = "LazyDev",
				module = "lazydev.integrations.blink",
				score_offset = 100,
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
})

require("avante").setup({
	provider = "ollama",
	providers = {
		ollama = {
			model = "devstral",
		},
		gemini = {
			model = "gemini-2.5-flash-preview-05-20",
		},
	},
	rag_service = {
		enabled = true,
		host_mount = os.getenv("HOME"),
		llm = {
			provider = "ollama",
			endpoint = "http://localhost:11434",
			api_key = "",
			model = "qwen3:14b",
			extra = nil,
		},
		embed = {
			provider = "ollama",
			endpoint = "http://localhost:11434",
			api_key = "",
			model = "nomic-embed-text",
			extra = {
				embed_batch_size = 10,
			},
		},
	},
	cursor_applying_provider = "ollama",
	behaviour = {
		enable_cursor_planning_mode = true,
	},
})

require("conform").setup({
	formatters_by_ft = {
		lua = { "stylua" },
		python = { "isort", "black" },
		rust = { "rustfmt", lsp_format = "fallback" },
		javascript = { "prettierd", "prettier", stop_after_first = true },
		typescript = { "prettierd", "prettier", stop_after_first = true },
		nix = { "nixpkgs-fmt" },
	},
	format_on_save = {
		timeout_ms = 500,
		lsp_format = "fallback",
	},
})

require("flash").setup()

require("oil").setup()

require("nvim-autopairs").setup()

require("gitsigns").setup()
