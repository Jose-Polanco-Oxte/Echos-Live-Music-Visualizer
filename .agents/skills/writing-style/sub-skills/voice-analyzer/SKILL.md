---
name: voice-analyzer
description: Analyze writing samples to create a portable voice profile and style guide. Use when setting up voice-matched AI writing, onboarding to a new project, or refreshing an outdated style guide.
use_when: User wants to create a voice profile, analyze writing samples for style, set up voice-matched AI writing, or create a VOICE.md style guide.
user-invocable: true
---

<objective>
Extract voice patterns from writing samples and generate a comprehensive, portable style guide (VOICE.md).

The output becomes infrastructure -- a reference document used every time you work with AI to maintain your authentic voice instead of producing generic content.
</objective>

<quick_start>
Provide 3-5 writing samples where your voice feels strongest (500-2000 words each). The skill will:

1. Analyze patterns across all samples
2. Identify your distinctive voice markers
3. Generate a VOICE.md style guide
4. Create a forbidden phrases list specific to your anti-patterns
5. Provide testing prompts to validate the guide

**Ideal samples:** Newsletter issues, blog posts, emails you're proud of, social media threads that felt "like you"

**Avoid:** Heavily edited corporate content, collaborative pieces, anything that felt forced
</quick_start>

<sample_gathering_guidance>
<what_makes_good_samples>
**Include samples that:**
- You wrote when feeling confident and natural
- Received feedback like "this sounds just like you"
- You'd be happy to write again
- Show your voice across different contexts (casual, professional, explanatory)
- Are at least 500 words (longer is better for pattern detection)

**Avoid samples that:**
- Were heavily edited by others
- Feel generic or corporate even to you
- Were written under heavy constraints
- Don't represent how you want to sound going forward
</what_makes_good_samples>

<minimum_requirements>
- **Minimum:** 3 samples, 500+ words each
- **Ideal:** 5-7 samples, 1000+ words each
- **Advanced:** 10+ samples including different formats (email, long-form, social)

More samples = more accurate pattern detection, but diminishing returns after 10.
</minimum_requirements>

<alternative_sources>
If you don't have strong writing samples:

**Voice memo transcription:** Record yourself explaining something you know well. Transcribe it. Your speaking patterns often reveal writing voice better than forced writing.

**Email archaeology:** Search sent mail for messages where you were being genuinely helpful, not performing professionalism.

**Chat/Slack messages:** Longer explanatory messages often show natural voice patterns.

**Old social media:** Before you started "performing" for algorithms.
</alternative_sources>
</sample_gathering_guidance>

<analysis_framework>
When analyzing samples, examine these dimensions:

<dimension name="sentence_patterns">
**Sentence Structure:**
- Average sentence length (short/punchy vs. long/flowing)
- Length variation (uniform vs. high variance)
- Sentence starters (do you vary, or repeat patterns?)
- Use of fragments for emphasis
- Complex vs. simple sentence construction
</dimension>

<dimension name="vocabulary_fingerprint">
**Word Choice:**
- Formality level (casual/conversational vs. professional/technical)
- Jargon usage (industry terms, insider language)
- Characteristic phrases you repeat
- Curse words or mild profanity patterns
- Filler words ("actually," "basically," "honestly")
- Intensifiers you favor ("really," "absolutely," "quite")
</dimension>

<dimension name="rhythm_and_flow">
**Paragraph Patterns:**
- Typical paragraph length
- How you transition between ideas
- Use of one-sentence paragraphs for emphasis
- Section structure and pacing
- How you open and close pieces
</dimension>

<dimension name="tone_markers">
**Voice Personality:**
- Humor style (dry, self-deprecating, none)
- Level of directness
- How you handle uncertainty (hedge vs. commit)
- Personal disclosure level
- Relationship with reader (peer, teacher, friend)
</dimension>

<dimension name="structural_habits">
**Organization:**
- How you use lists vs. prose
- Header/subheader patterns
- Use of examples and analogies
- How you introduce and conclude topics
- Formatting preferences (bold, italics, em-dashes)
</dimension>

<dimension name="opinion_expression">
**Stance and Authority:**
- How strongly you state opinions
- How you qualify claims
- Use of "I" vs. "we" vs. "you"
- How you handle disagreement or controversy
- Confidence level in assertions
</dimension>
</analysis_framework>

<output_format>
Generate a VOICE.md file with this structure:

```markdown
# Voice Profile: [Name]
Generated: [Date]
Based on: [X] writing samples ([total word count] words)

## Voice Summary
[2-3 sentence description of overall voice character]

## Core Voice Characteristics

### Sentence Patterns
- Average length: [X] words
- Variation: [Low/Medium/High]
- Notable patterns: [specific observations]

### Vocabulary Fingerprint
- Formality: [Casual/Conversational/Professional/Formal]
- Characteristic phrases: [list]
- Words to use freely: [list]

### Rhythm and Flow
- Paragraph style: [description]
- Transition patterns: [description]
- Pacing notes: [description]

### Tone Markers
- Primary tone: [description]
- Humor style: [description]
- Reader relationship: [description]

### Structural Habits
- List vs. prose preference: [description]
- Formatting patterns: [description]

### Opinion Expression
- Directness level: [1-10]
- Qualification style: [description]
- Authority stance: [description]

## The Forbidden List

### Never Use (These kill your voice)
- [phrase 1]
- [phrase 2]
- [etc.]

### Use Sparingly (Context-dependent)
- [phrase 1] - only when [context]
- [etc.]

### Watch for Clusters (OK alone, problematic together)
- [pattern description]

## Voice Maintenance

### Monthly Check
- Read 3 recent pieces aloud
- Do they still sound like you?
- Update this guide if voice has evolved

### Quarterly Refresh
- Gather new strong samples
- Re-run analysis
- Compare to this guide
- Update patterns that have changed

## Testing Prompts

Use these to validate the guide works:

**Test 1 - Short form:**
"Using my voice profile, write a 3-sentence response to [common scenario in your field]"

**Test 2 - Long form:**
"Using my voice profile, write the opening 2 paragraphs for a piece about [topic you know well]"

**Test 3 - Edge case:**
"Using my voice profile, write about [topic outside your usual content]"

Compare outputs to your natural writing. If they feel off, update the guide.
```
</output_format>

<analysis_process>
<step number="1" name="Initial Read">
Read all samples without analyzing. Get a feel for the overall voice impression. Note your gut reaction: what makes this writing distinctive?
</step>

<step number="2" name="Pattern Extraction">
Go through each dimension in the analysis framework. Pull specific examples from the samples. Look for patterns that appear across multiple samples (not one-offs).
</step>

<step number="3" name="Contrast Analysis">
Compare to generic AI output patterns. What does this writer do that AI typically doesn't? What AI patterns are absent from these samples?
</step>

<step number="4" name="Forbidden List Generation">
Based on the contrast analysis, identify phrases and patterns that would destroy this voice. These become the "never use" list.
</step>

<step number="5" name="Guide Assembly">
Compile findings into the VOICE.md format. Include specific examples from the samples to illustrate each pattern.
</step>

<step number="6" name="Validation Prompts">
Generate 3 test prompts tailored to this person's typical writing contexts. These will be used to verify the guide works.
</step>
</analysis_process>

<examples>
<example name="conversational_expert">
**Sample characteristics:** Newsletter writer, explains complex topics simply, uses humor and personal anecdotes

**Key findings:**
- Sentences vary wildly (5-40 words)
- Heavy use of "Here's the thing" and "The reality is"
- Self-deprecating humor about own mistakes
- One-sentence paragraphs for emphasis
- Direct address to reader ("you")
- Specific numbers and timeframes ("three hours later, no hyperbole")

**Forbidden list generated:**
- "It's worth noting that"
- "In today's digital landscape"
- "Leverage" as a verb
- Paired adjectives ("comprehensive and thorough")
- Any sentence starting with "Furthermore" or "Moreover"
</example>

<example name="technical_authority">
**Sample characteristics:** Engineering blog, detailed explanations, code examples, dry humor

**Key findings:**
- Longer sentences with technical precision
- Code-switches between casual and technical
- Humor through understatement
- Heavy use of concrete examples
- "Actually" and "technically" as qualifiers
- Lists for technical content, prose for opinions

**Forbidden list generated:**
- Vague claims without specifics
- Marketing superlatives ("revolutionary," "game-changing")
- Excessive hedging ("it might be argued")
- Emoji in technical sections
- "Simply" before complex explanations
</example>
</examples>

<integration_notes>
**Where to save VOICE.md:**
- Project-specific: `resources/VOICE.md` (for this project only)
- User-wide: `resources/voice/VOICE.md` (for all projects)
- Multiple profiles: `resources/voice/[context]-voice.md` (professional, casual, technical)

**Using with other skills:**
- `slop-detector` will reference VOICE.md for personalized pattern detection
- `voice-editor` uses VOICE.md to guide rewrites
- Include path to VOICE.md in project's CLAUDE.md for automatic loading

**Maintenance schedule:**
- Monthly: Quick read-aloud check (15 min)
- Quarterly: Full refresh with new samples (1 hour)
- After major voice shifts: Complete re-analysis
</integration_notes>

<success_criteria>
The voice analysis is complete when:
- [ ] All provided samples have been analyzed
- [ ] Each dimension in the analysis framework has findings
- [ ] VOICE.md file is generated with all sections
- [ ] Forbidden list contains at least 10 specific items
- [ ] 3 validation prompts are tailored to the user's context
- [ ] User has been shown where to save the file
- [ ] Testing process has been explained

**Quality check:** The generated guide should allow someone unfamiliar with the writer to produce content that readers would recognize as authentic.
</success_criteria>

<core_principle>
You're not trying to achieve perfection on attempt one. You're building infrastructure that improves with use. The first guide will be good but not perfect -- that's normal. Each piece written with this guide makes it more precise.

Voice doesn't live in first drafts. It lives in editing choices. The guide gives AI direction; your editing gives the work your actual voice.
</core_principle>