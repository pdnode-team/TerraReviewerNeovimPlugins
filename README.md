# terra-reviewer.nvim

Neovim client for the Terra waiting review queue. It calls one endpoint:

`GET https://api.terra.hackclub.com/review/queue?queue=review&filter=waiting`

## Install

```lua
{ "pdnode-team/TerraReviewerNeovimPlugins" }
```

Neovim 0.10 or newer, and `curl` on `PATH`.

## Use

```
:TerraSetApiKey
:TerraReview
:TerraClearApiKey
```

The key is saved at `stdpath("data")/terra-reviewer/api_key`. `:TerraReview` opens a fullscreen floating window. `<CR>` opens the item in a small card over the list, `r` refreshes, and `y` yanks the review id. `q` closes the card, then the queue.
