vim.cmd.colorscheme("catppuccin_mocha")

vim.g.mapleader = "\\"
vim.keymap.set("n", "<leader><space>", ":nohl<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fd", "<cmd>Telescope diagnostics<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { noremap = true, silent = true })
vim.opt.tabstop = 2

local undodir = vim.fn.stdpath('state') .. '/undo'
vim.fn.mkdir(undodir, 'p')
vim.opt.undodir = undodir
vim.opt.undofile = true

vim.lsp.enable('nixd')
vim.lsp.enable('nil_ls')
vim.lsp.enable('rust_analyzer')
vim.lsp.enable('ts_ls')
vim.lsp.enable('cssls')
vim.lsp.enable('tailwindcss')
vim.lsp.enable('html')
vim.lsp.enable('svelte')
vim.lsp.enable('pyright')
vim.lsp.enable('dockerls')
vim.lsp.enable('bashls')
vim.lsp.enable('clangd')
vim.lsp.enable('jdtls')
vim.lsp.enable('csharp_ls')
vim.lsp.enable('markdown_oxide')

require("blink.cmp").setup({
	signature = { enabled = true },
	snippets = { preset = 'luasnip' },
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

require('lualine').setup()

require('nvim-treesitter.configs').setup({
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

require('avante').setup({
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
	cursor_applying_provider = 'ollama',
	behaviour = {
		enable_cursor_planning_mode = true,
	},
})
