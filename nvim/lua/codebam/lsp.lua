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
				check = { command = "clippy" },
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
