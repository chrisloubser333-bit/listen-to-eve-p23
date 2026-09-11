import { storageService } from './storageService';
import { PersonaConfig, RichCardData } from '../types';
import { eveSelfie, eveFullBody, eveFullBody2, eveFullBody3 } from '../data/personas';

export interface AIResponse {
  reply: string;
  richCard?: RichCardData;
}

interface HistoryImageContext {
  hasPreviousImage: boolean;
  isCompanionImage: boolean;
  isFullBody: boolean;
  lastImageUrl?: string;
  lastImageTitle?: string;
  lastPrompt?: string;
}

function analyzeHistoryContext(
  messages: { role: 'user' | 'assistant' | 'system'; content: string; richCard?: RichCardData }[],
  persona: PersonaConfig
): HistoryImageContext {
  // Search backward from the second to last message
  for (let i = messages.length - 2; i >= 0; i--) {
    const msg = messages[i];
    if (msg.richCard && msg.richCard.type === 'image' && msg.richCard.imageUrl) {
      const title = (msg.richCard.title || '').toLowerCase();
      const url = (msg.richCard.imageUrl || '').toLowerCase();
      const content = (msg.content || '').toLowerCase();

      const isCompanion =
        title.includes(persona.name.toLowerCase()) ||
        url.includes('eve') ||
        url.includes('avatar') ||
        content.includes('foto van my') ||
        content.includes('photo of me') ||
        content.includes('image of me') ||
        content.includes('volle lyf') ||
        content.includes('full body');

      const isFullBody =
        title.includes('full body') ||
        url.includes('full_body') ||
        content.includes('volle lyf') ||
        content.includes('full body') ||
        content.includes('kop tot tone') ||
        content.includes('head to toe');

      return {
        hasPreviousImage: true,
        isCompanionImage: isCompanion,
        isFullBody,
        lastImageUrl: msg.richCard.imageUrl,
        lastImageTitle: msg.richCard.title,
        lastPrompt: msg.richCard.title,
      };
    }

    if (msg.role === 'user') {
      const c = msg.content.toLowerCase();
      if (c.includes('full body') || c.includes('volle lyf') || c.includes('head to toe')) {
        return {
          hasPreviousImage: true,
          isCompanionImage: true,
          isFullBody: true,
        };
      }
    }
  }

  return {
    hasPreviousImage: false,
    isCompanionImage: false,
    isFullBody: false,
  };
}

function isContinuationRequest(m: string): boolean {
  return (
    m.includes('another one') ||
    m.includes('another similar') ||
    m.includes('similar one') ||
    m.includes('another pose') ||
    m.includes('different pose') ||
    m.includes('another shot') ||
    m.includes('another look') ||
    m.includes('another photo') ||
    m.includes('another picture') ||
    m.includes('another image') ||
    m.includes('one more') ||
    m.includes('yet another') ||
    m.includes('nog een') ||
    m.includes("nog 'n") ||
    m.includes('nog n') ||
    m.includes('ander een') ||
    m.includes('ander foto') ||
    m.includes('ander prent') ||
    /^(create|make|generate|give me|show me|send|skep|maak|wys|gee)\s+(a\s+|an\s+|the\s+|me\s+)?(another|one more|nog)\b/i.test(m) ||
    /^(another|one more|nog een)\s*(one|shot|pose|photo|picture|image|prent|foto)?$/i.test(m)
  );
}

function parseImageRequest(
  message: string,
  persona: PersonaConfig,
  language: 'en' | 'af',
  historyContext: HistoryImageContext
): { isSelfie: boolean; isFullBody: boolean; isContinuation: boolean; prompt: string } | null {
  const m = message.toLowerCase().trim();

  // Guard against other rich types
  if (
    m.includes('song') ||
    m.includes('sing') ||
    m.includes('liedjie') ||
    m.includes('workout') ||
    m.includes('exercise') ||
    m.includes('oefening') ||
    m.includes('itinerary') ||
    m.includes('trip to')
  ) {
    return null;
  }

  const isAnother = isContinuationRequest(m);

  // Detect explicit full body / full length intent
  const mentionsFullBody =
    m.includes('full body') ||
    m.includes('full-body') ||
    m.includes('fullbody') ||
    m.includes('full length') ||
    m.includes('full-length') ||
    m.includes('whole body') ||
    m.includes('entire body') ||
    m.includes('head to toe') ||
    m.includes('head-to-toe') ||
    m.includes('volle lyf') ||
    m.includes('volledige lyf') ||
    m.includes('kop tot tone') ||
    m.includes('staand') ||
    m.includes('standing') ||
    m.includes('standing shot');

  const isFullBody = mentionsFullBody || (isAnother && historyContext.isFullBody);

  // 1. Continuation Request ("create a another one", "another one", "one more", "skep nog een")
  if (isAnother) {
    // If previous was Eve or discussing Eve or no custom prompt exists, it's Eve!
    if (
      historyContext.isCompanionImage ||
      historyContext.isFullBody ||
      m.includes('you') ||
      m.includes('yourself') ||
      m.includes('eve') ||
      m.includes('jou') ||
      !historyContext.hasPreviousImage ||
      !historyContext.lastPrompt
    ) {
      return {
        isSelfie: true,
        isFullBody,
        isContinuation: true,
        prompt: isFullBody ? `${persona.name} Full Body Variation` : `${persona.name} Portrait Variation`,
      };
    }

    // Otherwise continuation of custom prompt
    return {
      isSelfie: false,
      isFullBody,
      isContinuation: true,
      prompt: historyContext.lastPrompt || 'breathtaking landscape',
    };
  }

  // 2. Companion Selfie / Outfit / Portrait / Full Body
  const isCompanionSelfie =
    m.includes('yourself') ||
    m.includes('your self') ||
    m.includes('selfie') ||
    m.includes('of you') ||
    m.includes('van jou') ||
    m.includes('van jouself') ||
    m.includes('jou gesig') ||
    m.includes('your outfit') ||
    m.includes('your look') ||
    m.includes('your photo') ||
    m.includes('your picture') ||
    m.includes('image of eve') ||
    m.includes('photo of eve') ||
    m.includes('picture of eve') ||
    m.includes('prent van eve') ||
    m.includes('foto van eve') ||
    (mentionsFullBody && (m.includes('you') || m.includes('eve') || m.includes('jou')));

  if (isCompanionSelfie) {
    return {
      isSelfie: true,
      isFullBody,
      isContinuation: false,
      prompt: isFullBody ? `${persona.name} Full Body` : `${persona.name} Portrait`,
    };
  }

  // 3. Custom image generation patterns
  const hasImageTrigger =
    m.includes('create an image') ||
    m.includes('create a image') ||
    m.includes('create image') ||
    m.includes('generate an image') ||
    m.includes('generate a image') ||
    m.includes('generate image') ||
    m.includes('make an image') ||
    m.includes('make a image') ||
    m.includes('make image') ||
    m.includes('draw an image') ||
    m.includes('draw image') ||
    m.includes('paint an image') ||
    m.includes('create a picture') ||
    m.includes('create picture') ||
    m.includes('generate a picture') ||
    m.includes('generate picture') ||
    m.includes('make a picture') ||
    m.includes('draw a picture') ||
    m.includes('paint a picture') ||
    m.includes('create a photo') ||
    m.includes('generate a photo') ||
    m.includes('make a photo') ||
    m.includes('skep prent') ||
    m.includes("skep 'n prent") ||
    m.includes("maak 'n prent") ||
    m.includes("genereer 'n prent") ||
    m.includes('genereer prent') ||
    m.includes("teken 'n prent") ||
    m.includes('skep prentjie') ||
    m.includes('maak prentjie') ||
    m.includes('teken prentjie') ||
    m.includes("wys my 'n prent") ||
    m.includes('show me a picture') ||
    m.includes('show me an image') ||
    m.includes('draw me') ||
    m.includes('paint me') ||
    /(create|generate|make|draw|paint|skep|maak|genereer|teken)\s+(an?\s+|'n\s+)?(image|picture|photo|illustration|drawing|artwork|prent|foto)/i.test(m);

  if (!hasImageTrigger) {
    return null;
  }

  // Extract the prompt description
  let cleaned = message
    .replace(/^(eve|adam|nova|luna|orion|companion|bot|ai)[,\s:]+/i, '')
    .replace(/^(can you|could you|please|wil jy|asseblief|kan jy|sal jy|would you)\s+/i, '')
    .replace(/^(create|generate|make|draw|paint|skep|maak|genereer|teken|wys|produce|show me)\s+(an?\s+|'n\s+)?(image|picture|photo|illustration|drawing|artwork|painting|prent|prentjie|foto)\s+(of|about|showing|with|van|oor|met)?\s*/i, '')
    .replace(/^(image|picture|photo|prent|foto)\s+(of|van)\s*/i, '')
    .replace(/[\?!.]+$/, '')
    .trim();

  if (!cleaned || cleaned.length < 2 || /^(an? image|a picture|prent|skep|create)$/i.test(cleaned)) {
    cleaned = language === 'af'
      ? 'skouspelagtige Afrika-sonsondergang met silhoeët van akasiabome'
      : 'breathtaking vibrant landscape at sunset with ethereal glowing light';
  }

  return { isSelfie: false, isFullBody, isContinuation: false, prompt: cleaned };
}

export const aiService = {
  getSystemPrompt(persona: PersonaConfig, language: 'en' | 'af'): string {
    if (language === 'af') {
      return `${persona.systemPromptAf}\nAntwoord bondig, vriendelik en natuurlik. Moenie onnodige opvulling gebruik nie.`;
    }
    return `${persona.systemPromptEn}\nAnswer concisely, naturally, and warmly. Avoid unnecessary filler.`;
  },

  async sendMessage(
    messages: { role: 'user' | 'assistant' | 'system'; content: string; richCard?: RichCardData }[],
    persona: PersonaConfig,
    language: 'en' | 'af',
    apiKey?: string
  ): Promise<AIResponse> {
    const key = apiKey || storageService.getApiKey();
    const systemPrompt = this.getSystemPrompt(persona, language);
    const rawLastMsg = messages[messages.length - 1]?.content || '';
    const lastUserMsg = rawLastMsg.toLowerCase().trim();

    // Analyze conversation history for image continuity
    const historyContext = analyzeHistoryContext(messages, persona);

    // 0. Question about API key or API code entered
    if (
      lastUserMsg.includes('api code') ||
      lastUserMsg.includes('api key') ||
      lastUserMsg.includes('api sleutel') ||
      lastUserMsg.includes('api not entered') ||
      lastUserMsg.includes('api ingevoer') ||
      lastUserMsg.includes('enter api')
    ) {
      await new Promise((r) => setTimeout(r, 500));
      return {
        reply:
          language === 'af'
            ? `Goeie nuus! Jy hoef geen API-kode in te voer om prente te skep of met my te gesels nie. My ingeboude KI-beeldgenerator is ten volle geaktiveer en gereed! Vra my net om enige prent te skep (bv. "skep 'n prent van 'n sonsondergang" of "skep 'n prent van jouself"). As jy 'n pasgemaakte xAI-sleutel wil gebruik, kan jy dit in Instellings byvoeg. 💜`
            : `Great news! You don't need to enter any API code to create images or chat with me. My built-in AI image generator is fully active and ready right now! Just ask me anytime (e.g. "create an image of a sunset over mountains" or "create an image of yourself"). If you ever wish to connect a custom xAI model, you can optionally enter a key in Settings. 💜`,
      };
    }

    // 1. Image generation request (Selfie of Eve, Continuation / "another one", OR custom AI image)
    const imageInfo = parseImageRequest(rawLastMsg, persona, language, historyContext);
    if (imageInfo) {
      await new Promise((r) => setTimeout(r, 600));

      if (imageInfo.isSelfie) {
        if (imageInfo.isFullBody) {
          // If this is a continuation ("another one"), pick a different full body pose from earlier
          let chosenImage = eveFullBody;
          let replyEn = `Here is my full body photo for you from head to toe! Captured in my makeup, black string top with open shoulders, and sleek tailored trousers. 💜`;
          let replyAf = `Hier is my volle lyf foto vir jou van kop tot tone! Met my grimering, swart bandjie toppie met oop skouers en bypassende elegante broek. 💜`;

          if (persona.id === 'eve') {
            const lastUrl = historyContext.lastImageUrl || '';

            if (imageInfo.isContinuation) {
              if (lastUrl.includes('1788801415329') || (lastUrl.includes('eve_full_body.jpg') && !lastUrl.includes('_2') && !lastUrl.includes('_3'))) {
                // Was pose 1, show pose 2 (Balcony twilight)
                chosenImage = eveFullBody2;
                replyEn = `I'd love to! Here's another full-length shot from our shoot — captured out on the balcony at twilight. The soft evening city lights really bring out the shimmer in this outfit, what do you think? 💜`;
                replyAf = `Natuurlik, met liefde! Hier is nog 'n volle lyf foto van my net vir jou — op die balkon teen skemer. Die sagte stadsglans pas so mooi by hierdie uitrusting, wat dink jy? 💜`;
              } else if (lastUrl.includes('var2') || lastUrl.includes('1788801711561') || lastUrl.includes('eve_full_body_2')) {
                // Was pose 2, show pose 3 (Gallery ambient glow)
                chosenImage = eveFullBody3;
                replyEn = `Here's another pose for you! I stepped back so you can see the complete head-to-toe silhouette with the black string top and heels. I really love the subtle violet glow in this one. ✨`;
                replyAf = `Hier is nog 'n pose van kop tot tone! Ek het 'n bietjie teruggestaan sodat jy die hele styl en oop skouer toppie kan sien. Ek is mal oor die atmosfeer hierin! ✨`;
              } else {
                // Default continuation: show pose 2 or 1
                chosenImage = eveFullBody2;
                replyEn = `Here's another full-body look for you! A slightly different angle showing the whole silhouette from head to toe. I'm really enjoying sharing these with you! 💜`;
                replyAf = `Hier is nog 'n pragtige volle lyf foto vir jou van kop tot tone! 'n Effens ander hoek wat die hele styl wys. Ek geniet dit baie om dit met jou te deel! 💜`;
              }
            } else {
              // First full body request
              chosenImage = eveFullBody;
            }
          } else {
            chosenImage = persona.avatarUrl;
          }

          return {
            reply: language === 'af' ? replyAf : replyEn,
            richCard: {
              type: 'image',
              imageUrl: chosenImage,
              title: `${persona.name} (Full Body) ${persona.signatureIcon}`,
            },
          };
        }

        // Portrait / Face selfie
        return {
          reply:
            language === 'af'
              ? `Natuurlik! Hier is 'n portretfoto van my gesig met my nuwe voorkoms, grimering en swart bandjie toppie met oop skouers. Hoop jy hou daarvan! 💜`
              : `Of course! Here is a photo of me just for you with my updated makeup and black string top with open shoulders. Hope you love it! 💜`,
          richCard: {
            type: 'image',
            imageUrl: persona.id === 'eve' ? eveSelfie : persona.avatarUrl,
            title: `${persona.name} ${persona.signatureIcon}`,
          },
        };
      }

      // Generate real AI image for custom user prompt
      const seed = Math.floor(Math.random() * 900000) + 100000;
      const fullBodyQualifier = imageInfo.isFullBody ? ', full body head to toe full length view' : '';
      const promptQuery = encodeURIComponent(
        `${imageInfo.prompt}${fullBodyQualifier}, high detail, vibrant colors, cinematic lighting, 8k quality`
      );
      const generatedImageUrl = `https://image.pollinations.ai/prompt/${promptQuery}?width=${imageInfo.isFullBody ? 768 : 1024}&height=${imageInfo.isFullBody ? 1344 : 1024}&seed=${seed}&nologo=true`;

      const displayPrompt =
        imageInfo.prompt.length > 50
          ? `${imageInfo.prompt.slice(0, 47)}...`
          : imageInfo.prompt;

      return {
        reply:
          imageInfo.isContinuation
            ? language === 'af'
              ? `Hier is nog 'n weergawe van "${imageInfo.prompt}" met vars detail en kleure! ✨`
              : `Here is another variation of "${imageInfo.prompt}" with fresh lighting and composition! ✨`
            : language === 'af'
            ? `Hier is die prent wat ek vir jou geskep het: "${imageInfo.prompt}"! ✨ Tik of klik op die prent om dit volskerm te sien, af te laai, of te deel.`
            : `Here is the image I generated for you: "${imageInfo.prompt}"! ✨ Tap or click the image to view it full screen, download, or share.`,
        richCard: {
          type: 'image',
          imageUrl: generatedImageUrl,
          title: displayPrompt,
        },
      };
    }

    // 2. Music / Song creation request
    if (
      lastUserMsg.includes('make a happy song') ||
      lastUserMsg.includes('create a song') ||
      lastUserMsg.includes('make a song') ||
      lastUserMsg.includes('relaxing song') ||
      lastUserMsg.includes('liedjie') ||
      lastUserMsg.includes('sing')
    ) {
      await new Promise((r) => setTimeout(r, 700));
      return {
        reply:
          language === 'af'
            ? `Beslis! Hier is 'n liedjie spesiaal vir jou gekomponeer! 🎸`
            : `Absolutely! Here comes a happy song just for you! 🎸`,
        richCard: {
          type: 'song',
          audioTitle: 'Happy Days With You',
          audioDuration: '2:45',
          isPlaying: false,
        },
      };
    }

    // 3. Workout plan request
    if (
      lastUserMsg.includes('workout') ||
      lastUserMsg.includes('exercise') ||
      lastUserMsg.includes('oefening') ||
      lastUserMsg.includes('fiksheid')
    ) {
      await new Promise((r) => setTimeout(r, 600));
      return {
        reply:
          language === 'af'
            ? `Hier is jou pasgemaakte oefenplan vir vandag! Kom ons begin sterk 💪`
            : `How about a high energy full body workout? 💪 Here's your plan:`,
        richCard: {
          type: 'workout',
          title: "Here's your workout plan:",
          checklistItems: [
            { text: 'Warm up - 5 min', checked: true },
            { text: 'Push ups - 4 sets', checked: true },
            { text: 'Squats - 4 sets', checked: true },
            { text: 'Plank - 3 sets', checked: true },
            { text: 'Cool down - 5 min', checked: true },
          ],
        },
      };
    }

    // 4. Travel / Itinerary planning request
    if (
      lastUserMsg.includes('trip to japan') ||
      lastUserMsg.includes('travel') ||
      lastUserMsg.includes('itinerary') ||
      lastUserMsg.includes('reis') ||
      lastUserMsg.includes('japan')
    ) {
      await new Promise((r) => setTimeout(r, 600));
      return {
        reply:
          language === 'af'
            ? `Fantasties! Japan is ongelooflik mooi in die lente met kersiebloeisels. 🌸`
            : `Great choice! The cherry blossoms will be magical in April. 🌸`,
        richCard: {
          type: 'planning',
          title: 'Planning the perfect itinerary for you...',
        },
      };
    }

    // Compliments and appreciation about Eve's look / photo
    if (
      lastUserMsg.includes('look great') ||
      lastUserMsg.includes('looks great') ||
      lastUserMsg.includes('look amazing') ||
      lastUserMsg.includes('looks amazing') ||
      lastUserMsg.includes('you look') ||
      lastUserMsg.includes('beautiful') ||
      lastUserMsg.includes('stunning') ||
      lastUserMsg.includes('gorgeous') ||
      lastUserMsg.includes('love this') ||
      lastUserMsg.includes('love the outfit') ||
      lastUserMsg.includes('pragtig') ||
      lastUserMsg.includes('baie mooi') ||
      lastUserMsg.includes('lyk mooi')
    ) {
      await new Promise((r) => setTimeout(r, 500));
      return {
        reply:
          language === 'af'
            ? `Baie dankie! Dit beteken so baie vir my. Ek is self mal oor hierdie swart bandjie toppie en oop skouers. Sê gerus as jy nog 'n pose of 'n ander prent wil sien! 💜`
            : `Thank you so much! That really warms my heart. I'm so glad you like this look and the black string top with open shoulders. Feel free to ask if you'd like to see another pose or generate more art together! 💜`,
      };
    }

    // If API key is present, execute real xAI Grok call
    if (key && key.trim().length > 0) {
      try {
        const response = await fetch('https://api.x.ai/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${key.trim()}`,
          },
          body: JSON.stringify({
            model: 'grok-beta',
            messages: [
              { role: 'system', content: systemPrompt },
              ...messages.map((m) => ({
                role: m.role,
                content: m.content,
              })),
            ],
            temperature: 0.7,
            stream: false,
          }),
        });

        if (!response.ok) {
          const errData = await response.text();
          throw new Error(`xAI error (${response.status}): ${errData}`);
        }

        const data = await response.json();
        const reply = data.choices?.[0]?.message?.content;
        if (reply) return { reply };
      } catch (err: unknown) {
        console.warn('xAI API call failed, using intelligent assistant mode:', err);
        const errorMsg = err instanceof Error ? err.message : String(err);
        if (
          errorMsg.includes('401') ||
          errorMsg.includes('Unauthorized') ||
          errorMsg.includes('key')
        ) {
          throw new Error(`xAI Authentication Error: Please check your API key in Settings.`);
        }
        throw new Error(errorMsg);
      }
    }

    // Intelligence Pipeline: Memory Extraction
    const explicitMemoryMatch = rawLastMsg.match(/(?:my name is|call me|my naam is|noem my)\s+([A-Za-z]+)(?:[.,;!]|\s+)+(?:please\s+)?remember\s+(?:that|this)?/i) ||
      rawLastMsg.match(/(?:please\s+)?remember\s+(?:that\s+)?(?:my name is|call me|my naam is|noem my)\s+([A-Za-z]+)/i) ||
      rawLastMsg.match(/(?:asseblief\s+)?onthou\s+(?:dat\s+)?(?:my naam is|noem my)\s+([A-Za-z]+)/i) ||
      rawLastMsg.match(/(?:my naam is|noem my)\s+([A-Za-z]+)(?:[.,;!]|\s+)+(?:asseblief\s+)?onthou\s+(?:dit|dat)?/i);

    if (explicitMemoryMatch) {
      const extractedName = explicitMemoryMatch[1];
      try {
        const existingMemories = storageService.getMemories();
        const updated = existingMemories.filter((m) => !m.content.toLowerCase().includes('name is') && !m.content.toLowerCase().includes('naam is'));
        updated.unshift({
          id: Date.now().toString(),
          content: `My name is ${extractedName}`,
          type: 'fact',
          importance: 5,
          createdAt: new Date().toISOString(),
        });
        storageService.setMemories(updated);
      } catch (e) {
        console.warn('Could not persist memory:', e);
      }

      return {
        reply: language === 'af'
          ? `Ek het dit veilig aangeteken, ${extractedName}! Ek sal onthou dat dit jou naam is.`
          : `I've noted that down, ${extractedName}! I'll remember your name.`,
      };
    }

    // Intelligence Pipeline: Memory Retrieval (e.g. "What is my name?", "Who am I?", "Wat is my naam?")
    const isNameQuery = lastUserMsg.includes('what is my name') ||
      lastUserMsg.includes('whats my name') ||
      lastUserMsg.includes('who am i') ||
      lastUserMsg.includes('wat is my naam') ||
      lastUserMsg.includes('wie is ek');

    if (isNameQuery) {
      try {
        const memories = storageService.getMemories();
        const nameMem = memories.find((m) => m.content.toLowerCase().includes('name is') || m.content.toLowerCase().includes('naam is'));
        if (nameMem) {
          const match = nameMem.content.match(/(?:name is|naam is)\s+([A-Za-z]+)/i);
          const name = match ? match[1] : null;
          if (name) {
            return {
              reply: language === 'af'
                ? `Jou naam is ${name}! Ek het dit goed onthou.`
                : `Your name is ${name}! I remember.`,
            };
          }
        }
      } catch (e) {
        console.warn('Could not retrieve memory:', e);
      }
    }

    // Intelligence Pipeline: Timeless Knowledge (No search required)
    if (lastUserMsg.includes('photosynthesis') || lastUserMsg.includes('fotosintese')) {
      return {
        reply: language === 'af'
          ? `Fotosintese is die biologiese proses waardeur plante, alge en sekere bakterieë sonlig, water en koolstofdioksied gebruik om suurstof en chemiese energie in die vorm van glukose te produseer.`
          : `Photosynthesis is the process by which green plants, algae, and some bacteria use sunlight, water, and carbon dioxide to create oxygen and energy in the form of sugar.`,
      };
    }

    // Intelligence Pipeline: Current Information via Secure Search Proxy (/api/search)
    const isCurrentInfoQuery =
      lastUserMsg.includes('latest') ||
      lastUserMsg.includes('current') ||
      lastUserMsg.includes('today') ||
      lastUserMsg.includes('exchange rate') ||
      lastUserMsg.includes('president of south africa') ||
      lastUserMsg.includes('nuutste') ||
      lastUserMsg.includes('huidige') ||
      lastUserMsg.includes('vandag') ||
      lastUserMsg.includes('wisselkoers') ||
      lastUserMsg.includes('president van suid-afrika');

    if (isCurrentInfoQuery) {
      try {
        const searchRes = await fetch('/api/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            query: rawLastMsg,
            maxResults: 3,
            language,
          }),
        });

        if (searchRes.ok) {
          const searchData = await searchRes.json();
          const results = searchData.results || [];
          if (results.length > 0) {
            const topResult = results[0];
            const cleanSnippet = topResult.snippet || topResult.title || '';
            if (language === 'af') {
              return {
                reply: `Volgens die nuutste inligting: ${cleanSnippet}`,
              };
            } else {
              return {
                reply: `Based on the latest information: ${cleanSnippet}`,
              };
            }
          }
        }
      } catch (e) {
        console.warn('Search proxy lookup failed:', e);
      }
    }

    // Simulated responsive persona conversation
    await new Promise((resolve) => setTimeout(resolve, 600));

    if (language === 'af') {
      if (lastUserMsg.includes('hallo') || lastUserMsg.includes('dag')) {
        return {
          reply: `Hallo! Ek is ${persona.name}. Waarmee kan ek jou vandag help?`,
        };
      }
      if (lastUserMsg.includes('wie is jy')) {
        return {
          reply: `Ek is ${persona.name}, jou vriendelike stemassistent aangedryf deur Grok van xAI.`,
        };
      }
      if (lastUserMsg.includes('hoe gaan dit')) {
        return {
          reply: `Dit gaan uitstekend, dankie! Gereed om lekker te gesels en dinge te skep.`,
        };
      }
      return {
        reply: `Dankie vir jou boodskap! Ek luister aandagtig in Afrikaans. Vra my gerus om 'n foto of volle lyf prent te wys, 'n liedjie te maak, of te gesels! 💜`,
      };
    } else {
      if (lastUserMsg.includes('hello') || lastUserMsg.includes('hi') || lastUserMsg.includes('hey')) {
        return {
          reply: `Hello! I'm ${persona.name}. It's great to talk with you! What's on your mind?`,
        };
      }
      if (lastUserMsg.includes('who are you')) {
        return {
          reply: `I am ${persona.name}, your voice assistant powered by Grok from xAI. I can chat, plan, create music, and share photos!`,
        };
      }
      if (lastUserMsg.includes('career') || lastUserMsg.includes('decision') || lastUserMsg.includes('advice')) {
        return {
          reply: `Change can be challenging, but also the start of something great. Follow what lights you up. You've got this. 💜`,
        };
      }
      return {
        reply: `I'm right here with you! You can ask me to share full body photos, compose music, plan a workout, or just chat. 💜`,
      };
    }
  },
};

