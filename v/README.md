# Written in V

- [autoytdlp.vsh](#autoytdlpvsh)
  - [Dependencies:](#dependencies)
- [m2o.vsh (mkv-to-opus)](#m2ovsh-mkv-to-opus)
  - [Dependencies](#dependencies-1)

## autoytdlp.vsh

It runs `yt-dlp` in batch with opinionated config (at `~/.config/autoytdlp.json`).

Example config:

```json
[
  {
    "id": "PL89gW297DWyDiqy6mbVmICA6D40H-6_cu",
    "path": "/home/me/Videos/muics"
  },
  {
    "id": "PL89gW297DWyD5EmTcMCNYDgs6u0cR7n_w",
    "path": "/home/me/Videos/muics/e"
  }
]
```

### Dependencies:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/Installation)

## m2o.vsh (mkv-to-opus)

Extracts opus from an mkv file created with `yt-dlp -f "ba+bv" --embed-thumbnail --embed-metadata --merge-output-format mkv ...`, including the thumbnail (as front cover) and other embedded metadata.

### Dependencies

- [ffmpeg](https://ffmpeg.org/download.html)
- [graphicsmagick](http://www.graphicsmagick.org/download.html)
