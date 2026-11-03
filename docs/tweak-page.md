<!--
Start a wiki page titled exactly as the tweak is in Settings, paste this in, and add a link to it under its section in the sidebar.
Keep the sentences short. Delete the sections that don't apply, and these comments.
-->

One or two sentences on what it does.

<!-- The Settings preview, as an animated WebP pushed next to it in previews/:
     ffmpeg -i vertical-key.mp4 -vf fps=30,scale=800:500 frames/%04d.png
     img2webp -lossy -q 75 -m 6 -d 33 -mixed frames/*.png -o vertical-key.webp
     If the tweak looks different in each layout, put the vertical and horizontal ones side by side. -->

![Title, as in Settings](https://raw.githubusercontent.com/wiki/JaceThings/DiaTweaks/previews/vertical-key.webp)

## Turn it on

Open **Dia → Settings → Patches** and switch on **Title, as in Settings**. Or run:

```sh
diatweaks enable key
```

## Needs

<!-- Only if the patch sets .requires. -->

[Other tweak](Other-tweak). Settings only shows this switch while that's on, and `diatweaks enable key` offers to turn it on too.

## Works with

<!-- Only if another tweak changes what this one does, such as its .disabledBy. -->

## FAQ

<!-- Only questions about this tweak. General ones go in the main README. -->

<details>
<summary><strong>A question people ask?</strong></summary>

A short answer.

</details>
