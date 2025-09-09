# Yt-Audio-Fader

This script can be used to split an audio file into segments and merge them together, discarding portions of the audio file that you don't want. Fades can be added in between segments to make the jumps feel more natural.

## Supported formats

`.webm`
`.mp4`

## Usage

```
-i                  Input path of the audio file.
-timestamps         A comma separated list that determines where to segment the file.
-fade               A string that decides how to apply fades, and the fade duration.
```

### Fade options

All options are optional:

`start` - Will apply a fade in to the first segment.
`end` - Will apply a fade out to the last segment.
`in` - Will apply a fade in to every segment.
`out` - Will apply a fade out to every segment.
`duration` - Decides the duration of the fade. A 2 second default duration is applied if left out.

These options can be used by themselves, or combined however you wish and behaves as described above:

`"start"` - Applies a fade in to the first segment.
`"start,in"` - Applies a fade in to the first segment and every segment after that.
`"start,out"` - Applies a fade in to the first segment and fade out to every segment after that.
`"start,end"` - Applies a fade in to the first segment and fade out to the last segment.
`"start,in,end"` - Applies fade in to the first segment, a fade in to every segment except the first and the last, and a fade out to the last segment.
`"start,out,end"` - Applies fade in to the first segment, a fade in to every segment except the first and the last, and a fade out to the last segment.
`"start,in,out,end"` - Applies fade in to the first segment, a fade in/out to every segment except the first and the last, and a fade out to the last segment.
`"in,out"` - Applies fade in/out to every segment.
`"duration=5` - Applies a 5 second fade duration to every fade.

A complete example:

`-fade "in,out,duration=3"`

If the `-fade` argument is not used, no fades will be applied to the segments.

## Examples

`.\yt-audio-fader.ps1 -i ".\my-file.webm" -timestamps "ss=00:01:00,to=00:02:00"`
Outputs a one minute long segments from 00:01:00 to 00:02:00. No fades applied.

`.\yt-audio-fader.ps1 -i ".\my-file.webm" -timestamps "ss=00:01:00,to=00:02:00","ss=00:05:00,to=00:10:00","ss=00:13:00,to=00:15:00"`
Segments the file into the specified timestamps, and outputs a file merged from those segments. No fades applied.

`.\yt-audio-fader.ps1 -i ".\my-file.webm" -timestamps "ss=00:01:00,to=00:02:00","ss=00:05:00,to=00:10:00","ss=00:13:00"`
The last timestamp will make it so that the last segment will last from minute 00:13:00 to the end of the file. No fades applied.

`.\yt-audio-fader.ps1 -i ".\my-file.webm" -timestamps "ss=00:01:00,to=00:02:00","ss=00:05:00,to=00:10:00" -fade "in,out,duration=3"`
Apply a fade in/out to every segment with a 3 second duration.

`.\yt-audio-fader.ps1 -i ".\my-file.webm" -timestamps "ss=00:01:00"`
A lone seek time can be used as well, and will in this case segment the file from 00:01:00 to the end of the file.