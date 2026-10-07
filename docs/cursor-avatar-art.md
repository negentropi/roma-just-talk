# Cursor avatar artwork

The cursor companion uses original generated character art. Each style has five transparent PNG poses, greeting, listening, listening with closed eyes, working, and worried.

Assets live in `VoiceInk/Assets.xcassets/CursorAvatar-{style}-{pose}.imageset`. Each image is at most 384 pixels wide or tall. The renderer supplies motion and status labels.

The built-in image generation tool produced one transparent 2 by 2 sprite sheet per style. Equal-cell extraction and downsampling preserve transparency. No existing film or anime character is depicted.

The generation prompts used these character descriptions.

- Cartoon. A mint-green round woodland creature with oversized expressive eyes, short limbs, headphones, clean thick outlines, and coral cheeks.
- Disney. An original small golden-orange fox in classic Disney-inspired hand-painted animation style, with expressive eyes, rounded shapes, and a blue scarf.
- Anime. An original chibi companion with chestnut bob hair, a ribbon, brown eyes, a cream hoodie, a charcoal skirt, and sneakers, in clean cel-shaded anime style.

All prompts requested the same character and scale across four full-body perched poses. The greeting waves, the listening pose holds a hand to an ear, the working pose thinks beside a sparkle, and the worried pose has an orange exclamation mark. The background is transparent. No cursor, logo, or lettering is drawn into the art.

A follow-up image edit closed the listening character's eyes while preserving its pose, clothing, scale, and transparent background. The renderer crossfades the greeting for 900 milliseconds, blinks every 4.3 seconds, and adds subtle breathing, audio response, and working motion. Reduced Motion keeps the character still.
