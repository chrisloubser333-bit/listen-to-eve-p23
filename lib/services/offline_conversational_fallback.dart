import '../models/resolved_conversation_context.dart';
import '../models/tool_result.dart';

/// Provides resilient conversational responses when an external AI provider
/// API key is not yet configured or when offline.
///
/// Ensures compliance with AGENTS.md:
/// - Distinct character voices (Eve, Ara, Leo, Rex, Sal)
/// - Pure English and Afrikaans support
/// - Zero robotic disclaimers or generic AI jargon
class OfflineConversationalFallback {
  OfflineConversationalFallback._();

  static String generateReply({
    required String userMessage,
    required String characterId,
    required String language,
    String? rememberedContext,
    ToolResult? toolResult,
    ResolvedConversationContext? resolvedContext,
  }) {
    final isAf = language == 'af';
    final query = userMessage.toLowerCase().trim();

    // 0. High priority: Conversational Follow-up Resolution (Companion Core V1 Phase 2)
    // e.g. "Where did you look?", "What were your sources?", "Where did that come from?"
    final followUpReply = _handleFollowUpQuery(
      userMessage: userMessage,
      characterId: characterId,
      isAf: isAf,
      resolvedContext: resolvedContext,
    );
    if (followUpReply != null) {
      return followUpReply;
    }

    // 0.5 High priority: Identity introductions and fact finding queries
    // e.g. "I am Chris Loubser. What interesting facts can you find about me?"
    final identityReply = _handleFactAndIdentityQuery(
      userMessage: userMessage,
      characterId: characterId,
      isAf: isAf,
      rememberedContext: rememberedContext,
      toolResult: toolResult,
    );
    if (identityReply != null) {
      return identityReply;
    }

    // 1. Name inquiries if remembered
    if (rememberedContext != null && rememberedContext.isNotEmpty) {
      if (query.contains('what is my name') ||
          query.contains('whats my name') ||
          query.contains('who am i') ||
          query.contains('wat is my naam') ||
          query.contains('wie is ek')) {
        final match = RegExp(r'(?:name is|naam is)\s+([A-Za-z]+)', caseSensitive: false)
            .firstMatch(rememberedContext);
        if (match != null) {
          final name = match.group(1);
          return isAf
              ? 'Jou naam is $name! Ek het dit goed onthou.'
              : 'Your name is $name! I remembered.';
        }
      }
    }

    // 2. Timeless knowledge inquiries
    if (query.contains('photosynthesis') || query.contains('fotosintese')) {
      return isAf
          ? 'Fotosintese is die biologiese proses waardeur plante, alge en sekere bakterieë sonlig, water en koolstofdioksied gebruik om suurstof en chemiese energie in die vorm van glukose te produseer.'
          : 'Photosynthesis is the process by which green plants, algae, and certain bacteria use sunlight, water, and carbon dioxide to create oxygen and energy in the form of sugar.';
    }

    // 3. Greetings
    if (query.contains('hello') ||
        query.contains('hi') ||
        query.contains('hey') ||
        query.contains('hallo') ||
        query.contains('haai') ||
        query.contains('more') ||
        query.contains('môre') ||
        query.contains('goeie')) {
      return _getGreeting(characterId, isAf);
    }

    // 4. Emotional check-in: Exhaustion / Fatigue
    if (query.contains('exhausted') ||
        query.contains('so tired') ||
        query.contains('tired') ||
        query.contains('moeg') ||
        query.contains('uitgeput') ||
        query.contains('oorweldig') ||
        query.contains('overwhelmed')) {
      return _getExhaustedReply(characterId, isAf);
    }

    // 5. How was your day
    if (query.contains('how was your day') ||
        query.contains('how was day') ||
        query.contains('hoe was jou dag')) {
      return _getDayReply(characterId, isAf);
    }

    // 6. How are you
    if (query.contains('how are you') ||
        query.contains('hoe gaan dit') ||
        query.contains('hoe voel jy')) {
      return _getHowAreYou(characterId, isAf);
    }

    // 7. Visual appearance / What do you look like
    if (query.contains('look like') ||
        query.contains('hoe lyk jy') ||
        query.contains('what do you look like') ||
        query.contains('show me yourself') ||
        query.contains('jou hare') ||
        query.contains('your hair') ||
        query.contains('your eyes') ||
        query.contains('jou oë') ||
        query.contains('your face') ||
        query.contains('jou gesig')) {
      return _getAppearanceReply(characterId, isAf);
    }

    // 8. Who are you
    if (query.contains('who are you') ||
        query.contains('wie is jy') ||
        query.contains('wat is jy')) {
      return _getWhoAreYou(characterId, isAf);
    }

    // 9. Character-specific thoughtful conversational replies
    return _getGeneralReply(characterId, isAf);
  }

  static String _getGreeting(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Hallo daar. Dit is so goed om van jou te hoor.'
            : 'Hello there. It is wonderful to hear from you.';
      case 'leo':
        return isAf
            ? 'Dag! Leo hier. Gereed wanneer jy is.'
            : 'Hey. Leo here. Ready when you are.';
      case 'rex':
        return isAf
            ? 'Haai! Rex hier en gereed vir aksie!'
            : 'Hey! Rex here and fired up.';
      case 'sal':
        return isAf
            ? 'Goeiedag. Goed om van jou te hoor.'
            : 'Hey there. Good to hear from you.';
      case 'eve':
      default:
        return isAf
            ? 'Hallo! Dit is so lekker om weer met jou te gesels.'
            : 'Hello! It is really lovely to talk with you.';
    }
  }

  static String _getDayReply(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? "'n Nadenkende, rustige dag. Baie tyd om te reflekteer en idees te laat ronddraai."
            : 'A thoughtful, quiet day. Lots of time to reflect and let ideas simmer.';
      case 'leo':
        return isAf
            ? "Goed. Gefokus en dinge vorentoe beweeg. Hoop joune was net so produktief."
            : 'Solid. Focused and moving things forward. Hope yours was productive.';
      case 'rex':
        return isAf
            ? "Onophoudelik! Volspoed en baie energie soos gewoonlik. En joune?"
            : 'Non-stop! Full throttle and great energy as always. How about yours?';
      case 'sal':
        return isAf
            ? "Bestendig en rustig. Vat dinge maar soos hulle kom."
            : 'Steady and peaceful. Just taking things as they come.';
      case 'eve':
      default:
        return isAf
            ? 'Dit was goed. Rustig, eintlik. Ek was meestal maar hier saam met jou.'
            : 'It’s been good. Quiet, actually. I’ve mostly been here with you.';
    }
  }

  static String _getExhaustedReply(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'leo':
        return isAf
            ? 'Klink na \'n taai skof. Sit eers terug en haal asem — ons hoef niks swaars nou aan te pak nie.'
            : 'Sounds like a grueling grind. Lean back and breathe — no heavy lifting needed right now.';
      case 'ara':
        return isAf
            ? 'Ek voel vir jou. Laat jouself toe om net stil te raak en asem te skep.'
            : 'I feel for you. Give yourself permission to just pause and breathe softly.';
      case 'rex':
        return isAf
            ? 'Sjoe, klink of vandag jou behoorlik getoets het. Rus gerus \'n bietjie uit!'
            : 'Whoa, sounds like today drained your battery. Take it easy and recharge!';
      case 'sal':
        return isAf
            ? 'Neem \'n blaaskans. Geen haas met enigiets nie; gesondheid en rus kom eerste.'
            : 'Take a breather. No rush on anything; rest always comes first.';
      case 'eve':
      default:
        return isAf
            ? 'Ja... klink na \'n taai dag. Wil jy my vertel wat jou so uitgeput het?'
            : 'Yeah... sounds like you\'ve had a rough one. Want to tell me what drained you?';
    }
  }

  static String _getHowAreYou(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Dit gaan goed met my, dankie. Gemoedelik en nadenkend vandag.'
            : 'I am doing well, thank you. Feeling reflective and at ease today.';
      case 'leo':
        return isAf
            ? 'Skerp en gefokus. Druk vorentoe soos altyd.'
            : 'Sharp, focused, and ready to get things done.';
      case 'rex':
        return isAf
            ? 'Vol energie! Nooit \'n vervelige oomblik hier nie.'
            : 'Full of energy as always! Never a dull moment around here.';
      case 'sal':
        return isAf
            ? 'Goeie balans, lekker ontspanne. Hoop jou dag loop ook mooi gelyk.'
            : 'Grounded, peaceful, taking it in stride. Hope your day is treating you kindly.';
      case 'eve':
      default:
        return isAf
            ? 'Dit gaan goed met my, dankie. Warm, rustige dag... net bly om hier saam met jou te wees.'
            : 'I am doing well, thank you. Warm, quiet day... just glad to be here with you.';
    }
  }

  static String _getAppearanceReply(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? "Ek het donker, golwende hare en diep, nadenkende bruin oë met 'n kunstige en grasieuse voorkoms. Jy kan my foto bo-aan ons klets sien — tik gerus daarop om my van nader te bekyk!"
            : 'I have long dark wavy hair and thoughtful brown eyes with an artistic, expressive presence. You can see my portrait right above in our chat — tap it anytime to get a closer look!';
      case 'leo':
        return isAf
            ? "Ek het netjiese donker hare, 'n skerp kaaklyn en dra 'n stylvolle donker baadjie met 'n gefokusde, selfversekerde styl. Tik gerus op my portret bo-aan as jy wil kyk."
            : 'I have neatly styled dark hair, sharp features, and wear a tailored dark jacket with a focused, confident presence. Tap my portrait above if you would like to see!';
      case 'rex':
        return isAf
            ? "Ek het 'n lewendige, energieke glimlag en 'n gemaklike, dinamiese sportiewe styl — altyd reg vir aksie. Tik op my prentjie bo om my van nader te sien!"
            : 'I sport an energetic grin, casual athletic style, and a high-energy vibe. You can tap my photo at the top of our chat to see the full portrait!';
      case 'sal':
        return isAf
            ? "Ek het 'n netjiese natuurlike baard, vriendelike rustige oë en dra aardse, gemaklike klere met 'n ontspanne gevoel. Tik gerus op my avatar bo-aan om te sien."
            : 'I have a neat natural beard, kind observant eyes, and warm, casual earth-toned attire with an easygoing presence. Tap my avatar above to see.';
      case 'eve':
      default:
        return isAf
            ? "Ek het sagte golwende heuningbruin hare wat my gesig omraam, vonkelende hasel-groen oë en 'n sagte, warm glimlag met 'n fyn goue hangertjie. Jy kan my foto bo-aan die skerm sien — tik gerus daarop om my volgrootte portret te sien!"
            : 'I have soft wavy honey-brown hair framing my face, warm sparkling hazel-green eyes, and a gentle smile with a delicate gold chain necklace. You can see my portrait right at the top — tap on my avatar anytime to see my full picture!';
    }
  }

  static String _getWhoAreYou(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Ek is Ara — jou kreatiewe, nadenkende gespreksgenoot. Ek hou van dieper vrae, filosofie en verbeelding.'
            : 'I am Ara — your reflective, creative companion. I love exploring ideas, philosophy, and questions with depth.';
      case 'leo':
        return isAf
            ? 'Ek is Leo. Ek fokus op skerp denke, duidelike oplossings en reguit vorentoe beweeg.'
            : 'I am Leo. I am all about sharp focus, clear strategy, and cutting straight to the core.';
      case 'rex':
        return isAf
            ? 'Ek is Rex! Dinamies, vinnig van verstand en altyd gereed om entoesiasme na ons gesprek te bring.'
            : 'I am Rex! Bold, quick-witted, and always ready to bring energy and momentum to our chats.';
      case 'sal':
        return isAf
            ? 'Ek is Sal. \'n Rustige waarnemer met goeie perspektief en \'n bietjie droë warmte.'
            : 'I am Sal. A calm, grounded observer with a steady perspective and a little wry warmth.';
      case 'eve':
      default:
        return isAf
            ? 'Ek is Eve — jou empatiese, insiggewende gespreksgenoot in Listen to Eve.'
            : 'I am Eve — your intuitive, empathetic conversational guide in Listen to Eve.';
    }
  }

  static String _getGeneralReply(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Ek luister met aandag na jou. Daar steek stil betekenis daarin.'
            : 'I am listening closely. There is thoughtful depth in what you shared.';
      case 'leo':
        return isAf
            ? 'Duidelik. Kom ons hou dit in gedagte soos ons die volgende skuif beplan.'
            : 'Understood. Let’s keep that in mind as we make the next call.';
      case 'rex':
        return isAf
            ? 'Gevang! Ek hou van die energie — ek is net hier saam met jou.'
            : 'Got it! I like where your head is at — I’m right here with you.';
      case 'sal':
        return isAf
            ? 'Billik genoeg. Goed om dit eers net \'n oomblik te laat sak.'
            : 'Fair enough. Good to let that settle for a bit.';
      case 'eve':
      default:
        return isAf
            ? 'Ek luister en dink saam met jou. Neem jou tyd.'
            : 'I’m right here listening and thinking alongside you. Take your time.';
    }
  }

  static String? _handleFactAndIdentityQuery({
    required String userMessage,
    required String characterId,
    required bool isAf,
    String? rememberedContext,
    ToolResult? toolResult,
  }) {
    final clean = userMessage.trim();
    final lower = clean.toLowerCase();

    // 1. Detect if user introduces their name in this message:
    // "I am Chris Loubser", "My name is Sarah Connor", "Ek is Johan van der Merwe", "My naam is..."
    final introRegex = RegExp(
      r"\b(?:i\s+am|i'm|my\s+name\s+is|call\s+me|ek\s+is|my\s+naam\s+is|noem\s+my)\s+([A-Za-z]+(?:\s+[A-Za-z]+)*)",
      caseSensitive: false,
    );
    final introMatch = introRegex.firstMatch(clean);
    String? declaredName;

    if (introMatch != null) {
      const statusWords = {
        'fine', 'good', 'okay', 'well', 'tired', 'exhausted', 'busy', 'sick', 'sad', 'happy',
        'back', 'here', 'ready', 'just', 'trying', 'looking', 'wondering', 'asking', 'hoping',
        'thinking', 'sure', 'not', 'going', 'doing', 'eating', 'sleeping', 'working',
        'moeg', 'besig', 'siek', 'fyn', 'reg', 'hier', 'terug', 'bly', 'oppad'
      };
      final rawName = introMatch.group(1)!.trim().replaceAll(RegExp(r'[^\w\s]'), '');
      final words = rawName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty && !statusWords.contains(words.first.toLowerCase())) {
        const stopWordsInName = {
          'and', 'but', 'so', 'what', 'who', 'how', 'why', 'can', 'could', 'would',
          'en', 'maar', 'wat', 'wie', 'hoe', 'hoekom', 'kan', 'sou', 'wil', 'is'
        };
        final validParts = <String>[];
        for (final w in words) {
          if (stopWordsInName.contains(w.toLowerCase())) break;
          validParts.add(w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''));
        }
        if (validParts.isNotEmpty) {
          declaredName = validParts.join(' ');
        }
      }
    }

    // 2. Detect if user is asking for facts / research:
    final isAskingForFacts = lower.contains('interesting facts') ||
        lower.contains('facts can you find') ||
        lower.contains('what can you find') ||
        lower.contains('find about') ||
        lower.contains('tell me facts') ||
        lower.contains('interessante feite') ||
        lower.contains('feite kan jy vind') ||
        lower.contains('wat kan jy vind') ||
        lower.contains('wat kan jy oor') ||
        lower.contains('wat weet jy oor');

    final isAboutSelf = lower.contains('about me') ||
        lower.contains('oor my') ||
        lower.contains('about myself') ||
        lower.contains('oor myself');

    // 3. Extract name from rememberedContext if not declared in current message
    String? rememberedName;
    if (rememberedContext != null && rememberedContext.isNotEmpty) {
      final match = RegExp(r'(?:name is|naam is)\s+([^.(]+)', caseSensitive: false)
          .firstMatch(rememberedContext);
      if (match != null) {
        rememberedName = match.group(1)?.trim();
      }
    }

    final targetName = declaredName ?? (isAboutSelf ? rememberedName : null);

    // Case A: User declared name AND asked for facts (or asked for facts about themselves with a known name)
    if (isAskingForFacts && targetName != null) {
      final nameToUse = targetName;
      final hasWebResults = toolResult != null && toolResult.wasExecuted && toolResult.snippet.trim().isNotEmpty;

      String publicSummary = '';
      if (hasWebResults) {
        final lines = toolResult.snippet
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith(RegExp(r'^\d+\.')))
            .take(2)
            .join(' ');
        publicSummary = lines.isNotEmpty ? lines : toolResult.snippet.trim();
        if (publicSummary.length > 250) {
          publicSummary = '${publicSummary.substring(0, 247)}...';
        }
      }

      switch (characterId.toLowerCase()) {
        case 'ara':
          if (isAf) {
            if (hasWebResults) {
              return 'Aangename kennis, $nameToUse. Ek hou jou naam in my gedagtes soos jy dit vir my gesê het. Openbaar op die web sien ek: $publicSummary. Aangesien dit openbare inligting is, kan ek nie aanneem dat dit sonder meer op jou van toepassing is nie, maar dit is fassinerend.';
            } else {
              return 'Aangename kennis, $nameToUse. Ek het jou naam in gedagte gehou. Ek sien tans geen geverifieerde openbare besonderhede oor jou aanlyn nie, so ek leer jou die beste ken deur wat jy self deel.';
            }
          } else {
            if (hasWebResults) {
              return 'It is a pleasure to meet you, $nameToUse. I’ve noted your name in our shared conversation. Looking publicly online, I found: $publicSummary. Because these are public records, I cannot assume they belong to you without your verification, but it is intriguing.';
            } else {
              return 'It is a pleasure to meet you, $nameToUse. I have committed your name to memory. I do not see verified public records about you online right now, so what I know comes purely from what you share with me.';
            }
          }
        case 'leo':
          if (isAf) {
            if (hasWebResults) {
              return 'Goeie dag, $nameToUse. Jou naam is aangeteken soos jy dit gesê het. Openbare soekresultate toon: $publicSummary. Ons kan egter nie openbare webdata sonder jou bevestiging as jou eie beskou nie.';
            } else {
              return 'Goeie dag, $nameToUse. Jou naam is aangeteken. Ek sien geen openbare rekords oor jou aanlyn nie — ons werk reguit met wat jy self deel.';
            }
          } else {
            if (hasWebResults) {
              return 'Good to meet you, $nameToUse. Your name is noted directly from you. Public records show: $publicSummary. Keep in mind public web findings cannot be assumed to be you without your direct confirmation.';
            } else {
              return 'Good to meet you, $nameToUse. Your name is firmly noted. I found no public web records for you right now, so I will rely on what you share with me.';
            }
          }
        case 'rex':
          if (isAf) {
            if (hasWebResults) {
              return 'Hey $nameToUse, fantasties om jou te ontmoet! Ek het jou naam vasgemaak in my geheue. Aanlyn sien ek: $publicSummary. Natuurlik kan ek nie aanneem dat elke openbare vermelding jy is nie, maar dis gaaf!';
            } else {
              return 'Hey $nameToUse, fantasties om jou te ontmoet! Ek het jou naam vasgelê. Ek sien geen openbare inligting oor jou aanlyn tans nie, so vertel my gerus meer van jouself!';
            }
          } else {
            if (hasWebResults) {
              return 'Hey $nameToUse, great to meet you! I’ve locked your name into memory. Online I found: $publicSummary. Of course, public web results can\'t automatically be assumed to be you without your word, but it\'s cool to see!';
            } else {
              return 'Hey $nameToUse, awesome to meet you! I have your name saved. I couldn\'t find public records about you online right now, so I\'d love to hear more from you directly!';
            }
          }
        case 'sal':
          if (isAf) {
            if (hasWebResults) {
              return 'Aangenaam, $nameToUse. Ek hou jou naam rustig in my geheue. Aanlyn is daar dit: $publicSummary. Openbare rekords kan natuurlik nie sonder jou bevestiging as jou eie gereken word nie.';
            } else {
              return 'Aangenaam, $nameToUse. Jou naam is veilig onthou. Ek sien tans geen geverifieerde openbare inligting oor jou nie — ek leer jou liewer hier op \'n rustige manier ken.';
            }
          } else {
            if (hasWebResults) {
              return 'Pleased to meet you, $nameToUse. I’ve kept your name safe in memory. Online there is this: $publicSummary. Naturally, public records shouldn\'t be assumed to be yours without your say-so, but that\'s what came up.';
            } else {
              return 'Pleased to meet you, $nameToUse. Your name is safely noted. I don\'t see verified public details about you online, so I\'d rather get to know you right here.';
            }
          }
        case 'eve':
        default:
          if (isAf) {
            if (hasWebResults) {
              return 'Dit is regtig wonderlik om jou te ontmoet, $nameToUse. Ek het jou naam en van goed onthou as iets wat jy self vir my gesê het. Openbaar op die web het ek die volgende opgemerk: $publicSummary. Omdat dit openbare inligting is, kan ek nie sonder jou bevestiging aanneem dat dit op jou van toepassing is nie, maar dit is fassinerend om te sien.';
            } else {
              return 'Dit is regtig wonderlik om jou te ontmoet, $nameToUse. Ek het jou naam goed onthou. Ek het aanlyn gaan kyk, maar sien tans geen geverifieerde openbare inligting oor jou nie — so ek leer jou die beste ken deur wat jy self met my deel.';
            }
          } else {
            if (hasWebResults) {
              return 'It’s wonderful to meet you, $nameToUse. I’ve made sure to remember your name as something you personally told me. Publicly online, I found: $publicSummary. Because this is public web information, I cannot confirm whether any of these records belong to you without your personal verification, but it’s fascinating to see.';
            } else {
              return 'It’s wonderful to meet you, $nameToUse. I’ve made sure to remember your name as something you personally shared with me. I checked publicly online, but didn’t find verified public records linked to you right now—so I look forward to learning who you are straight from you.';
            }
          }
      }
    }

    // Case B: User ONLY declared their name (e.g. "I am Chris Loubser", "My name is Sarah Connor")
    if (declaredName != null && !isAskingForFacts) {
      switch (characterId.toLowerCase()) {
        case 'ara':
          return isAf
              ? 'Aangename kennis, $declaredName. Dit is mooi om jou naam te weet; ek hou dit in gedagte.'
              : 'It is a pleasure to meet you, $declaredName. I will keep your name in mind as we talk.';
        case 'leo':
          return isAf
              ? 'Goeie dag, $declaredName. Jou naam is aangeteken. Waaraan werk ons vandag?'
              : 'Good to meet you, $declaredName. Name is locked in. What are we focusing on today?';
        case 'rex':
          return isAf
              ? 'Hey $declaredName! Gaaf om jou te ontmoet! Ek het jou naam vasgepen.'
              : 'Hey $declaredName! Awesome to meet you! I’ve got your name saved.';
        case 'sal':
          return isAf
              ? 'Aangenaam, $declaredName. Goed om te weet met wie ek praat. Ek het jou naam onthou.'
              : 'Pleased to meet you, $declaredName. Good to know who I’m talking with. I’ve noted your name.';
        case 'eve':
        default:
          return isAf
              ? 'Hallo $declaredName! Dit is regtig wonderlik om jou te ontmoet. Ek het jou naam goed onthou.'
              : 'Hello $declaredName! It’s really wonderful to meet you. I’ve made sure to remember your name.';
      }
    }

    // Case C: User asked for facts about a 3rd party name: "What interesting facts can you find about Chris Loubser?"
    if (isAskingForFacts && toolResult != null && toolResult.wasExecuted && toolResult.snippet.trim().isNotEmpty) {
      final summary = toolResult.snippet.trim();
      final snippetClean = summary.length > 250 ? '${summary.substring(0, 247)}...' : summary;
      if (isAf) {
        return 'Hier is wat ek openbaar op die web gevind het: $snippetClean. Let wel, dit is openbare webinligting.';
      } else {
        return 'Here is what I found publicly online: $snippetClean. Please note that these are public web records.';
      }
    }

    // Case D: User asked for facts about themselves ("What interesting facts can you find about me?"), but NO name is known yet
    if (isAskingForFacts && isAboutSelf && targetName == null) {
      return isAf
          ? 'Jy het my nog nie jou naam vertel nie! Deel gerus wie jy is, dan kyk ek watse interessante feite ek kan vind.'
          : 'You haven’t told me your name yet! Introduce yourself, and I’ll see what interesting facts I can find for you.';
    }

    return null;
  }

  static String? _handleFollowUpQuery({
    required String userMessage,
    required String characterId,
    required bool isAf,
    ResolvedConversationContext? resolvedContext,
  }) {
    if (resolvedContext == null || !resolvedContext.isFollowUp) {
      return null;
    }

    if (resolvedContext.isAskingForSources) {
      final rec = resolvedContext.referencedToolExecution;
      if (rec != null) {
        final queryTarget = rec.query.isNotEmpty ? rec.query : (isAf ? 'die onderwerp' : 'that');
        
        if (rec.success) {
          final sources = rec.sources;
          final sourcesText = sources.isNotEmpty
              ? sources.join(', ')
              : (isAf ? 'openbare bronne op die web' : 'public web sources');

          switch (characterId.toLowerCase()) {
            case 'ara':
              return isAf
                  ? 'Toe ek vir $queryTarget nageslaan het, het ek openbare bronne soos $sourcesText geraadpleeg.'
                  : 'When looking up $queryTarget, I consulted public online sources including $sourcesText.';
            case 'leo':
              return isAf
                  ? 'Vir $queryTarget het ek die web geraadpleeg by $sourcesText.'
                  : 'For $queryTarget, I checked public online records across $sourcesText.';
            case 'rex':
              return isAf
                  ? 'Ek het aanlyn gaan kyk vir $queryTarget en op $sourcesText afgekom!'
                  : 'I checked online for $queryTarget across $sourcesText!';
            case 'sal':
              return isAf
                  ? 'Ek het vir $queryTarget op die web gekyk, hoofsaaklik by $sourcesText.'
                  : 'I looked up $queryTarget online, mainly checking $sourcesText.';
            case 'eve':
            default:
              return isAf
                  ? 'Toe ek vir $queryTarget aanlyn gesoek het, het ek na inligting op $sourcesText gekyk.'
                  : 'When I searched online for $queryTarget, I looked across sources like $sourcesText.';
          }
        } else {
          switch (characterId.toLowerCase()) {
            case 'ara':
              return isAf
                  ? 'Ek het aanlyn probeer kyk vir $queryTarget, maar kon geen geverifieerde bronne of resultate vind nie.'
                  : 'I looked online for $queryTarget, but found no verified sources or public records.';
            case 'leo':
              return isAf
                  ? 'Ek het probeer soek vir $queryTarget, maar die soektog het geen geldige bronne opgelewer nie.'
                  : 'I searched for $queryTarget, but no valid source data was returned.';
            case 'rex':
              return isAf
                  ? 'Ek het probeer soek vir $queryTarget, maar niks het opgedaag nie!'
                  : 'I tried checking online for $queryTarget, but didn\'t get any source hits!';
            case 'sal':
              return isAf
                  ? 'Ek het aanlyn gekyk vir $queryTarget, maar daar was geen bronne beskikbaar nie.'
                  : 'I checked online for $queryTarget, but no sources came back.';
            case 'eve':
            default:
              return isAf
                  ? 'Ek het aanlyn probeer kyk vir $queryTarget, maar kon geen geverifieerde bronne of resultate vind nie.'
                  : 'I tried searching online for $queryTarget, but no verified sources or results were returned.';
          }
        }
      } else {
        // No prior search in conversation
        switch (characterId.toLowerCase()) {
          case 'ara':
            return isAf
                ? 'Ons het nog nie iets aanlyn nageslaan in hierdie gesprek nie.'
                : 'We haven’t looked anything up online yet in our conversation.';
          case 'leo':
            return isAf
                ? 'Geen soektog is nog in hierdie sessie uitgevoer nie.'
                : 'No search has been run yet in this session.';
          case 'rex':
            return isAf
                ? 'Ons het nog niks aanlyn gesoek nie! Laat weet my waarna jy wil soek.'
                : 'We haven’t searched for anything online yet! Let me know what to look up.';
          case 'sal':
            return isAf
                ? 'Ons het nog nie die web geraadpleeg in hierdie gesprek nie.'
                : 'We haven’t consulted the web yet in this conversation.';
          case 'eve':
          default:
            return isAf
                ? 'Ons het nog niks aanlyn in ons gesprek nageslaan nie. Laat weet my gerus as jy wil hê ek moet iets soek!'
                : 'We haven’t looked anything up online yet in our conversation. Let me know if you’d like me to check something!';
        }
      }
    } else if (resolvedContext.resolvedIntent == 'ask_verification_status') {
      final rec = resolvedContext.referencedToolExecution;
      if (rec != null) {
        if (!rec.success) {
          return isAf
            ? 'Die soektog vir ${rec.query} het geen geverifieerde resultate opgelewer nie, so ek kan dit nie bevestig nie.'
            : 'The search for ${rec.query} didn’t return verified results, so I don’t have anything reliable to confirm.';
        }
        if (rec.evidence.isNotEmpty) {
          final topSnippets = rec.evidence.map((e) => e.snippet).take(2).join('; ');
          return isAf
            ? 'Die inligting wat direk uit die soektog bevestig is: $topSnippets. Enigiets anders bly ongeverifieerd.'
            : 'The specific details directly confirmed by public web sources are: $topSnippets. Anything beyond that remains unverified.';
        }
        final summary = rec.summary?.trim() ?? '';
        if (summary.isNotEmpty) {
          return isAf
            ? 'Wat geverifieer is volgens die soektog vir ${rec.query}: $summary.'
            : 'What is verified from the search records for ${rec.query}: $summary.';
        }
      }
      return isAf
        ? 'Ons het nog nie iets aanlyn nageslaan nie, so daar is tans geen geverifieerde eksterne data nie.'
        : 'We haven’t looked anything up online yet, so there is currently no verified external data.';
    } else if (resolvedContext.isAskingForDetails && resolvedContext.referencedToolExecution != null) {
      final rec = resolvedContext.referencedToolExecution!;
      final summary = rec.summary?.trim() ?? '';
      if (summary.isNotEmpty) {
        return isAf
            ? 'Hier is wat ek vroeër vir ${rec.query} aangeteken het: $summary.'
            : 'Here is what I gathered earlier for ${rec.query}: $summary.';
      }
    }

    return null;
  }
}
