# TODO
#
# - The code that fades start, end, in/out is almost identical. Refactor to reduce redundancy.
# - Add error handling for ffmpeg/ffprobe commands.
# - Add option to add text file with file names and timestamps to process files in bulk.
# - Add option to specify fade at the start of the file, end of the file, or both.
# - Add option to not have fade at the start of the file, end of the file, or both.

# Testing data
# "ss=00:02:40,to=00:04:40","ss=00:16:37,to=01:31:21","ss=01:50:00,to=03:15:05"

param (
	[Parameter(Mandatory)]$i,
	[Parameter(Mandatory)][string[]]$timestamps,
	[string]$fade
)

# .DESCRIPTION
#
# Retrieves the fade types from the -fade argument.
function Get-FadeTypes {
	param (
		[string]$Fade
	)

	return $Fade -split "[,\s]+"
}

# .DESCRIPTION
#
# Retrieves the fade duration from the -fade argument.
function Get-FadeDuration {
	param (
		[string]$Fade
	)

	if ($Fade -match "duration=(\d+)") {
		return [int]$Matches[1]
	}

	return 2 # Default fade duration
}

# .DESCRIPTION
#
# Retrieves the duration of a media file using ffprobe.
function Get-Duration {
	param (
		[string]$Path
	)

	return ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$Path"
}

# .DESCRIPTION
#
# Returns the fading start & end times, and fade their respective fade durations.
function Get-FadeAlgo {
	param (
		[bool]$FadeIn,
		[bool]$FadeOut,
		[int]$FileDuration,
		[int]$FadeDuration
	)

	$result = ""

	if ($FadeIn) {
		$result += "afade=type=in:start_time=0:duration=$FadeDuration"
	}

	if ($FadeOut) {
		if ($result -ne "") {
			$result += ","
		}

		$result += "afade=type=out:start_time=$($FileDuration - $FadeDuration):duration=$FadeDuration"
	}

	return $result
}

# .DESCRIPTION
#
# Retrieves the codec of a media file using ffprobe.
function Get-FileCodec {
	param (
		[string]$File
	)

	$codec = ffprobe "$File" -show_streams 2>&1 | Select-String "(?:codec_name=)(\w+)"

	return $codec.Matches[0].Groups[1].Value
}

# .DESCRIPTION
#
# Maps input codec names to libcodec names used by ffmpeg.
function Get-LibCodec {
	param (
		[string]$Codec
	)

	switch ($Codec) {
		"aac" { return "aac" }
		"opus" { return "libopus" }
		default { throw "Unsupported codec: $Codec" }
	}
}

# .DESCRIPTION
#
# Splits a media file into segments based on provided timestamps.
function Split-File {
	param (
		[string]$Path,
		[string[]]$Timestamps
	)

	$File = Get-Item "$Path"

	for ($idx = 0; $idx -lt $Timestamps.Count; $idx++) {
		$stamps = $Timestamps[$idx]
		$ss = [regex]::split($stamps, "[,\s]+")[0]
		$to = [regex]::split($stamps, "[,\s]+")[1]

		if ($ss -match "ss=\d\d:\d\d:\d\d") {
			$ss = [regex]::split($ss, "ss=")
			$ss = "$ss".trim()
		} else {
			$ss = $null
		}

		if ($to -match "to=\d\d:\d\d:\d\d") {
			$to = [regex]::split($to, "to=")
			$to = "$to".trim()
		} else {
			$to = $null
		}

		if ($null -ne $ss -and $null -eq $to) {
			$null = ffmpeg -i $File.FullName -ss $ss -codec copy "$temp_dir\$("split_$idx" + $File.Extension)" #2>&1
		} elseif ($null -ne $ss) {
			$null = ffmpeg -i $File.FullName -ss $ss -to $to -codec copy "$temp_dir\$("split_$idx" + $File.Extension)" #2>&1
		}
	}
}

# .DESCRIPTION
#
# Retrieves the bitrate of a media file using ffprobe.
function Get-FileBitrate {
	param (
		[string]$Path
	)

	return ffprobe -v error -select_streams a:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$Path"
}

# .DESCRIPTION
#
# Retrieves the split files from the temporary directory.
function Get-Splits {
	param (
		[string]$TempDir
	)

	return Get-ChildItem -Path "$TempDir" -File -Filter "split_*" | Sort-Object -Property Name
}

# .DESCRIPTION
#
# Applies a fade effect to an audio file using ffmpeg.
function Add-Fade {
    param (
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$FadeAlgo,
        [Parameter(Mandatory)] [string]$Bitrate,
        [Parameter(Mandatory)] [string]$Codec,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    ffmpeg -i $InputPath -af $FadeAlgo -b:a $Bitrate -c:a $Codec $OutputPath
}

# .DESCRIPTION
#
# Retrieves or creates an "edited" directory to store processed files.
function Get-EditedDir {
	param (
		[string]$Path
	)

	$dir = $null

	try {
		$dir = Get-Item "$Path\edited" -ErrorAction Stop
	} catch {
		$dir = New-Item "$Path" -Name "edited" -ItemType "Directory"
	}

	return $dir
}

# .DESCRIPTION
#
# Retrieves or creates a temporary directory for processing files.
function Get-TempDir {
	param (
		[string]$Path
	)

	$dir = $null

	try {
		$dir = Get-Item "$Path\temp" -ErrorAction Stop
	} catch {
		$dir = New-Item "$Path" -Name "temp" -ItemType "Directory"
	}

	return $dir
}

# .DESCRIPTION
#
# Validates the input file path and ensures it points to a file, not a directory.
function Get-InputFile {
	param (
		[string]$Path
	)

	$file = Get-Item "$Path"

	if ($file.PSIsContainer) {
		throw "Path points to a directory, not a file."
	}

	return $file
}

# .DESCRIPTION
#
# Applies fade effects to a given audio file based on specified parameters.
# Returns the file object of the faded audio file.
function Fader {
	param (
		[string]$Path,
		[bool]$FadeIn,
		[bool]$FadeOut,
		[int]$FadeDur,
		[string]$FileBitrate,
		[string]$LibCodec,
		[string]$TempDir,
		[int]$Idx
	)

	$file_dur = Get-Duration -Path $Path
	$fade_algo = Get-FadeAlgo -FadeIn $FadeIn -FadeOut $FadeOut -FileDuration $file_dur -FadeDuration $FadeDur
	$fade_file = "fade_$Idx" + $file.Extension

	Add-Fade -InputPath $Path -FadeAlgo $fade_algo -Bitrate $FileBitrate -Codec $LibCodec -OutputPath "$TempDir\$fade_file"

	return Get-Item "$TempDir\$fade_file"
}

# .DESCRIPTION
#
# Processes split files by applying fade effects as specified.
# Returns an array of strings formatted for ffmpeg concatenation.
function Get-ProcessedFiles {
	param (
		[string]$TempDir,
		[string]$Fade,
		[string]$FileBitrate,
		[string]$LibCodec
	)

	$split_files = @(Get-Splits -TempDir $TempDir)
	$fade_types = Get-FadeTypes -Fade $Fade
	$files = @()

	if ($fade_types -contains "start") {
		$fade_dur = Get-FadeDuration -Fade $Fade
		$path = $split_files[0].FullName
		$fade_file = Fader -Path $path -FadeIn $true -FadeOut $false -FadeDur $fade_dur -FileBitrate $FileBitrate -LibCodec $LibCodec -TempDir $TempDir -Idx 0

		$files += "file '$($fade_file.Name)'"
	}

	if ($fade_types -contains "in" -or $fade_types -contains "out") {
		$fade_in = $fade_types -contains "in"
		$fade_out = $fade_types -contains "out"
		$fade_dur = Get-FadeDuration -Fade $Fade

		$idx = if ($fade_types -contains "start") { 1 } else { 0 }
		$length = if ($fade_types -contains "end") { $split_files.length - 1 } else { $split_files.length }

		for ($idx; $idx -lt $length; $idx++) {
			$path = $split_files[$idx].FullName

			$fade_file = Fader -Path $path -FadeIn $fade_in -FadeOut $fade_out -FadeDur $fade_dur -FileBitrate $FileBitrate -LibCodec $LibCodec -TempDir $TempDir -Idx $idx

			$files += "file '$($fade_file.Name)'"
		}
	} else {
		$idx = if ($fade_types -contains "start") { 1 } else { 0 }
		$length = if ($fade_types -contains "end") { $split_files.length - 1 } else { $split_files.length }

		for ($idx; $idx -lt $length; $idx++) {
			$files += "file '$($split_files[$idx].Name)'"
		}
	}

	if ($fade_types -contains "end") {
		$idx = ($split_files.length - 1)
		$fade_dur = Get-FadeDuration -Fade $Fade
		$path = $split_files[$idx].FullName
		$fade_file = Fader -Path $path -FadeIn $false -FadeOut $true -FadeDur $fade_dur -FileBitrate $FileBitrate -LibCodec $LibCodec -TempDir $TempDir -Idx $idx

		$files += "file '$($fade_file.Name)'"
	}

	return $files
}

# .DESCRIPTION
#
# Creates a text file listing all processed files for ffmpeg concatenation.
function CreateConcatenationFile {
	param (
		[string]$TempDir,
		[string[]]$ProcessedFiles
	)

	if (!(Test-Path -Path "$TempDir\files.txt")) {
		$null = New-Item -Path "$TempDir" -Name "files.txt" -ItemType "File" -Value $($ProcessedFiles | Out-String)
	}
}

# .DESCRIPTION
#
# Concatenates processed audio files into a single output file using ffmpeg.
function ConcatenateTemporaryFiles {
	param (
		[string]$TempDir,
		[string]$EditedDir,
		[string]$FileName
	)

	ffmpeg -f concat -i "$TempDir\files.txt" -c copy "$EditedDir\$FileName"
}

# .DESCRIPTION
#
# Removes the temporary directory and its contents.
function RemoveTemporaryFiles {
	param (
		[string]$TempDir
	)

	Remove-Item $TempDir -Recurse
}

function Main {
	$file = Get-InputFile -Path "$i"
	$file_bitrate = Get-FileBitrate -Path "$i"
	$in_codec = Get-FileCodec -File "$i"
	$lib_codec = Get-LibCodec -Codec "$in_codec"
	$edited_dir = Get-EditedDir -Path $file.Directory
	$temp_dir = Get-TempDir -Path $edited_dir

	Split-File -Path "$i" -Timestamps $timestamps
	
	$processed_files = Get-ProcessedFiles -TempDir $temp_dir -Fade $fade -FileBitrate $file_bitrate -LibCodec $lib_codec

	CreateConcatenationFile -TempDir $temp_dir -ProcessedFiles $processed_files
	ConcatenateTemporaryFiles -TempDir $temp_dir -EditedDir $edited_dir -FileName $file.Name
	RemoveTemporaryFiles -TempDir $temp_dir
}

Main
