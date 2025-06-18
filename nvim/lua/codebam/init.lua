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

local undodir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(undodir, "p")
vim.opt.undodir = undodir
vim.opt.undofile = true

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

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true

local function on_attach(client, bufnr)
	local bufopts = { noremap = true, silent = true, buffer = bufnr }
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
	vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
	vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, bufopts)
	vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, bufopts)
	vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
end

local function find_root(patterns)
	return vim.fs.dirname(vim.fs.find(patterns, { upward = true })[1])
end

local lsp_servers = {
	{
		name = "nixd",
		cmd = { "nixd" },
		filetypes = { "nix" },
		root_dir = find_root({ "flake.nix", ".git" }),
		settings = {},
	},
	{
		name = "nil_ls",
		cmd = { "nil" },
		filetypes = { "nix" },
		root_dir = find_root({ "flake.nix", ".git" }),
		settings = {},
	},
	{
		name = "rust_analyzer",
		cmd = { "rust-analyzer" },
		filetypes = { "rust" },
		root_dir = find_root({ "Cargo.toml", ".git" }),
		settings = {
			["rust-analyzer"] = {
				checkOnSave = { command = "clippy" },
			},
		},
	},
	{
		name = "ts_ls",
		cmd = { "typescript-language-server", "--stdio" },
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
		root_dir = find_root({ "package.json", "tsconfig.json", ".git" }),
		settings = {},
	},
	{
		name = "cssls",
		cmd = { "vscode-css-language-server", "--stdio" },
		filetypes = { "css", "scss", "less" },
		root_dir = find_root({ "package.json", ".git" }),
		settings = {
			css = { validate = true },
			scss = { validate = true },
			less = { validate = true },
		},
	},
	{
		name = "tailwindcss",
		cmd = { "tailwindcss-language-server", "--stdio" },
		filetypes = {
			"html",
			"css",
			"scss",
			"javascript",
			"javascriptreact",
			"typescript",
			"typescriptreact",
			"svelte",
		},
		root_dir = find_root({ "tailwind.config.js", "tailwind.config.cjs", "package.json", ".git" }),
		settings = {},
	},
	{
		name = "html",
		cmd = { "vscode-html-language-server", "--stdio" },
		filetypes = { "html" },
		root_dir = find_root({ "package.json", ".git" }),
		settings = {},
	},
	{
		name = "svelte",
		cmd = { "svelteserver", "--stdio" },
		filetypes = { "svelte" },
		root_dir = find_root({ "package.json", ".git" }),
		settings = {},
	},
	{
		name = "pyright",
		cmd = { "pyright-langserver", "--stdio" },
		filetypes = { "python" },
		root_dir = find_root({ "pyproject.toml", "setup.py", ".git" }),
		settings = {
			python = {
				analysis = {
					autoSearchPaths = true,
					useLibraryCodeForTypes = true,
					diagnosticMode = "workspace",
				},
			},
		},
	},
	{
		name = "dockerls",
		cmd = { "docker-langserver", "--stdio" },
		filetypes = { "dockerfile" },
		root_dir = find_root({ "Dockerfile", ".git" }),
		settings = {},
	},
	{
		name = "bashls",
		cmd = { "bash-language-server", "start" },
		filetypes = { "sh", "bash" },
		root_dir = find_root({ ".git" }),
		settings = {},
	},
	{
		name = "clangd",
		cmd = { "clangd" },
		filetypes = { "c", "cpp", "objc", "objcpp" },
		root_dir = find_root({ "compile_commands.json", ".git" }),
		settings = {},
	},
	{
		name = "jdtls",
		cmd = { "jdtls" },
		filetypes = { "java" },
		root_dir = find_root({ "pom.xml", "build.gradle", ".git" }),
		settings = {},
	},
	{
		name = "csharp_ls",
		cmd = { "csharp-ls" },
		filetypes = { "cs" },
		root_dir = find_root({ "sln", "csproj", ".git" }),
		settings = {},
	},
	{
		name = "markdown_oxide",
		cmd = { "markdown-oxide" },
		filetypes = { "markdown" },
		root_dir = find_root({ ".git" }),
		settings = {},
	},
}

local function start_lsp(server)
	local client_id = vim.lsp.start({
		name = server.name,
		cmd = server.cmd,
		capabilities = capabilities,
		on_attach = on_attach,
		settings = server.settings,
		root_dir = server.root_dir,
	})
	if not client_id then
		vim.notify("Failed to start " .. server.name, vim.log.levels.ERROR)
	end
end

for _, server in ipairs(lsp_servers) do
	vim.api.nvim_create_autocmd("FileType", {
		pattern = server.filetypes,
		callback = function()
			start_lsp(server)
		end,
	})
end

vim.diagnostic.config({
	virtual_text = true,
	signs = true,
	update_in_insert = false,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		local bufnr = args.buf
		if client and client.server_capabilities.inlayHintProvider then
			vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
		end
	end,
})
