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
	if type(patterns) == "string" then
		patterns = { patterns }
	end
	local found_files = vim.fs.find(patterns, { upward = true, type = "file" })
	if #found_files > 0 and found_files[1] then
		return vim.fs.dirname(found_files[1])
	end
	local git_root = vim.fs.find({ ".git" }, { upward = true, type = "directory" })
	if #git_root > 0 and git_root[1] then
		return vim.fs.dirname(git_root[1])
	end
	return vim.fn.getcwd()
end

local lsp_servers = {
	{
		name = "nixd",
		cmd = { "nixd" },
		filetypes = { "nix" },
		root_dir = function(fname)
			return find_root({ "flake.nix", ".git" })
		end,
		settings = {},
	},
	{
		name = "nil_ls",
		cmd = { "nil" },
		filetypes = { "nix" },
		root_dir = function(fname)
			return find_root({ "flake.nix", ".git" })
		end,
		settings = {
			["nil"] = {
				nix = {
					formatterPath = "nixpkgs-fmt",
				},
				diagnostics = {
					workspace = true,
				},
			},
		},
	},
	{
		name = "rust_analyzer",
		cmd = { "rust-analyzer" },
		filetypes = { "rust" },
		root_dir = function(fname)
			return find_root({ "Cargo.toml", ".git" })
		end,
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
		root_dir = function(fname)
			return find_root({ "package.json", "tsconfig.json", ".git" })
		end,
		settings = {},
	},
	{
		name = "cssls",
		cmd = { "vscode-css-language-server", "--stdio" },
		filetypes = { "css", "scss", "less" },
		root_dir = function(fname)
			return find_root({ "package.json", ".git" })
		end,
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
			"javascriptreact",
			"typescriptreact",
			"svelte",
			"vue",
			"astro",
		},
		root_dir = function(fname)
			return find_root({
				"tailwind.config.js",
				"tailwind.config.cjs",
				"tailwind.config.ts",
				"package.json",
				".git",
			})
		end,
		settings = {},
	},
	{
		name = "html",
		cmd = { "vscode-html-language-server", "--stdio" },
		filetypes = { "html" },
		root_dir = function(fname)
			return find_root({ "package.json", ".git" })
		end,
		settings = {},
	},
	{
		name = "svelte",
		cmd = { "svelteserver", "--stdio" },
		filetypes = { "svelte" },
		root_dir = function(fname)
			return find_root({ "svelte.config.js", "package.json", ".git" })
		end,
		settings = {},
	},
	{
		name = "pyright",
		cmd = { "pyright-langserver", "--stdio" },
		filetypes = { "python" },
		root_dir = function(fname)
			return find_root({ "pyproject.toml", "setup.py", "requirements.txt", ".git" })
		end,
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
		root_dir = function(fname)
			return find_root({ "Dockerfile", ".git" })
		end,
		settings = {},
	},
	{
		name = "bashls",
		cmd = { "bash-language-server", "start" },
		filetypes = { "sh", "bash" },
		root_dir = function(fname)
			return find_root({ ".shellcheckrc", ".git" })
		end,
		settings = {},
	},
	{
		name = "clangd",
		cmd = { "clangd" },
		filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
		root_dir = function(fname)
			return find_root({ "compile_commands.json", ".clangd", ".clang-tidy", ".git" })
		end,
		settings = {},
	},
	{
		name = "jdtls",
		cmd = { "jdtls" },
		filetypes = { "java" },
		root_dir = function(fname)
			return find_root({ "pom.xml", "build.gradle", "settings.gradle", ".git" })
		end,
		settings = {},
	},
	{
		name = "csharp_ls",
		cmd = { "csharp-ls" },
		filetypes = { "cs" },
		root_dir = function(fname)
			return find_root({ ".sln", ".csproj", ".git" })
		end,
		settings = {},
	},
	{
		name = "markdown_oxide",
		cmd = { "markdown-oxide" },
		filetypes = { "markdown" },
		root_dir = function(fname)
			return find_root({ ".git" }) or vim.fn.getcwd()
		end,
		settings = {},
	},
}

local function start_lsp(server_config, bufnr_arg)
	local effective_root_dir
	if type(server_config.root_dir) == "function" then
		effective_root_dir = server_config.root_dir(vim.api.nvim_buf_get_name(bufnr_arg))
	else
		effective_root_dir = server_config.root_dir
	end

	local client_id = vim.lsp.start({
		name = server_config.name,
		cmd = server_config.cmd,
		capabilities = capabilities,
		on_attach = function(client, bufnr_on_attach)
			on_attach(client, bufnr_on_attach)
			-- Custom on_attach logic per server can be added here if needed
		end,
		settings = server_config.settings,
		root_dir = effective_root_dir,
		-- filetypes = server_config.filetypes
	})

	if not client_id or client_id == 0 then -- client_id 0 can sometimes indicate an issue
		vim.notify("LSP: Failed to start " .. server_config.name, vim.log.levels.ERROR)
	elseif client_id == -1 then
		vim.notify("LSP: " .. server_config.name .. " is already started for this buffer.", vim.log.levels.INFO)
	else
		-- vim.notify("LSP: Started " .. server_config.name .. " (ID: " .. client_id .. ") with root: " .. (effective_root_dir or "nil"), vim.log.levels.INFO)
	end
end

local buffer_lsp_started = {}

for _, server_config in ipairs(lsp_servers) do
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("LspAutoStart_" .. server_config.name, { clear = true }),
		pattern = server_config.filetypes,
		callback = function(args)
			local bufnr = args.buf
			if not buffer_lsp_started[bufnr] then
				buffer_lsp_started[bufnr] = {}
			end
			if not buffer_lsp_started[bufnr][server_config.name] then
				start_lsp(server_config, bufnr)
				buffer_lsp_started[bufnr][server_config.name] = true
			end
		end,
	})
end

vim.diagnostic.config({
	virtual_text = true,
	signs = true,
	update_in_insert = false,
	underline = true,
	severity_sort = true,
	float = {
		source = "always",
		border = "rounded",
	},
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		local bufnr = args.buf
		if client and client.server_capabilities.inlayHintProvider then
			vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
		end
		-- You can also add buffer-local keymaps here if they depend on client capabilities
		-- if client and client.name == "nil_ls" then
		--   vim.notify("nil_ls attached to buffer " .. bufnr, vim.log.levels.INFO)
		-- end
	end,
})

vim.api.nvim_create_autocmd("BufDelete", {
	pattern = "*",
	callback = function(args)
		if buffer_lsp_started[args.buf] then
			buffer_lsp_started[args.buf] = nil
		end
	end,
})
