--- @since 25.5.31
---
--- Office document preview for yazi.
---
--- Rewritten from macydnah/office.yazi, which stopped at 41ebef8 in September
--- 2025 and no longer runs against yazi 26.x. Three API differences:
---
---   ya.preview_widgets  REMOVED. It cleared the text widgets before showing
---                       an image; ya.image_show alone is now sufficient, and
---                       calling it fails with "attempt to call a nil value".
---
---   ya.manager_emit     RENAMED to ya.mgr_emit. The original used both names
---                       in the same file, so page-stepping was broken even
---                       before the peek failure.
---
---   Err()               Kept, but the original passed a pre-formatted string
---                       as the format argument, so a '%' in a filename would
---                       have been interpreted as a format specifier.
---
--- HOW IT WORKS: LibreOffice converts one page to PDF, pdftoppm rasterises
--- that to JPEG, and yazi displays the JPEG from its cache. Two subprocesses
--- per page, which is why the result is cached rather than regenerated on
--- every cursor move.

local M = {}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return
	end

	-- Honour the configured image delay, minus however long the conversion
	-- already took. Without the subtraction a slow document would wait twice.
	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	ya.image_show(cache, job.area)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		-- mgr_emit, not manager_emit. The latter was renamed and no longer
		-- exists, which is why scrolling through pages did nothing.
		ya.mgr_emit("peek", {
			math.max(0, cx.active.preview.skip + step),
			only_if = job.file.url,
		})
	end
end

function M:doc2pdf(job)
	local dir = "/tmp/yazi-" .. ya.uid() .. "/" .. ya.hash("office.yazi") .. "/"

	-- LibreOffice quirks worth knowing before changing any of this:
	--
	--   1. It writes errors to STDOUT whether or not it succeeded, so the
	--      exit status is the only reliable signal.
	--   2. It always writes to the filesystem — there is no way to get the
	--      converted document on a pipe.
	--   3. The pdf:draw_pdf_Export filter needs LITERAL double quotes in its
	--      options, hence the single-quoted Lua string below.
	local libreoffice = Command("libreoffice")
		:arg({
			"--headless",
			"--convert-to",
			'pdf:draw_pdf_Export:{"PageRange":{"type":"string","value":"' .. job.skip + 1 .. '"}}',
			"--outdir",
			dir,
			tostring(job.file.url),
		})
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not libreoffice then
		return nil, Err("Failed to run `libreoffice`. Is it installed and named exactly that?")
	end

	if not libreoffice.status.success then
		local output = libreoffice.stdout .. libreoffice.stderr
		local version = (output:match("LibreOffice .+") or ""):gsub("%\n.*", "")
		local detail = (output:match("Error:? .+") or ""):gsub("%\n.*", "")
		if version ~= "" or detail ~= "" then
			ya.err("%s %s", version, detail)
		end
		return nil, Err("Failed to convert `%s` to a temporary PDF", job.file.name)
	end

	-- LibreOffice names the output after the input with the extension
	-- replaced, and gives no way to choose. So the path is reconstructed
	-- rather than read from its output.
	local pdf = dir .. job.file.name:gsub("%.[^%.]+$", ".pdf")

	local handle = io.open(pdf, "r")
	if not handle then
		return nil, Err("Converted PDF missing at `%s`", pdf)
	end
	handle:close()

	return pdf
end

function M:preload(job)
	local cache = ya.file_cache(job)

	-- Already rendered. Two subprocesses per page is expensive enough that
	-- this check is the difference between usable and not.
	if not cache or fs.cha(cache) then
		return true
	end

	local pdf, err = self:doc2pdf(job)
	if not pdf then
		return true, err
	end

	local output, cmd_err = Command("pdftoppm")
		:arg({
			"-singlefile",
			"-jpeg",
			"-jpegopt",
			"quality=" .. rt.preview.image_quality,
			"-f",
			1,
			tostring(pdf),
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	-- Remove the intermediate PDF whether or not rasterising worked —
	-- otherwise a failing document leaves a file in /tmp on every peek.
	local removed, rm_err = fs.remove("file", Url(pdf))
	if not removed then
		ya.err("Failed to remove %s: %s", pdf, tostring(rm_err))
	end

	if not output then
		return true, Err("Failed to run `pdftoppm`: %s", tostring(cmd_err))
	end

	if not output.status.success then
		-- Stepping past the last page: clamp to it rather than reporting an
		-- error, so holding the key down stops at the end instead of
		-- flashing failures.
		local pages = tonumber(output.stderr:match("the last page %((%d+)%)")) or 0
		if job.skip > 0 and pages > 0 then
			ya.mgr_emit("peek", {
				math.max(0, pages - 1),
				only_if = job.file.url,
				upper_bound = true,
			})
			return true
		end
		return true, Err("Failed to rasterise %s: %s", job.file.name, output.stderr)
	end

	return fs.write(cache, output.stdout)
end

return M
