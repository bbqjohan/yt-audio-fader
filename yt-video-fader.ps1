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

function Main {
	$file = Get-InputFile -Path "$i"
	$file_bitrate = Get-FileBitrate -Path "$i"
	$in_codec = Get-FileCodec -File "$i"
	$lib_codec = Get-LibCodec -Codec "$in_codec"
	$edited_dir = Get-EditedDir -Path $file.Directory
	$temp_dir = Get-TempDir -Path $edited_dir

	Split-File -Path "$i" -Timestamps $timestamps

	# Add fade in/out for splits.

	$files = @()

	# Wrap in an array to always get back an array. Get-ChildItem returns a single object if only
	# one file is found, and an array if multiple are found.
	$split_files = @(Get-Splits -TempDir $temp_dir)
	$fade_types = Get-FadeTypes -Fade $fade

	if ($fade_types -contains "in" -or $fade_types -contains "out") {
		$fade_in = $fade_types -contains "in"
		$fade_out = $fade_types -contains "out"
		$fade_dur = Get-FadeDuration -Fade $fade

		for ($idx = 0; $idx -lt $split_files.length; $idx++) {
			$path = $split_files[$idx].fullname

			$file_dur = Get-Duration -Path $path
			$fade_algo = Get-FadeAlgo -FadeIn $fade_in -FadeOut $fade_out -FileDuration $file_dur -FadeDuration $fade_dur
			$fade_file = "fade_$idx" + $file.Extension

			Add-Fade -InputPath $path -FadeAlgo $fade_algo -Bitrate $file_bitrate -Codec $lib_codec -OutputPath "$temp_dir\$fade_file"

			$files += "file '$fade_file'"
		}
	}

	if (!(Test-Path -Path "$temp_dir\files.txt")) {
		$null = New-Item -Path "$temp_dir" -Name "files.txt" -ItemType "File" -Value $($files | Out-String)
	}

	ffmpeg -f concat -i "$temp_dir\files.txt" -c copy "$edited_dir\$($file.Name)"

	Remove-Item $temp_dir -Recurse
}

Main
