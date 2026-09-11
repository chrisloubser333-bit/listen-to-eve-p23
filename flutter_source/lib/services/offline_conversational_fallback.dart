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
  }) {
    final isAf = language == 'af';
    final query = userMessage.toLowerCase().trim();

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

    // 4. How are you
    if (query.contains('how are you') ||
        query.contains('hoe gaan dit') ||
        query.contains('hoe voel jy')) {
      return _getHowAreYou(characterId, isAf);
    }

    // 5. Visual appearance / What do you look like
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

    // 6. Who are you
    if (query.contains('who are you') ||
        query.contains('wie is jy') ||
        query.contains('wat is jy')) {
      return _getWhoAreYou(characterId, isAf);
    }

    // 6. Character-specific thoughtful conversational replies
    return _getGeneralReply(characterId, isAf);
  }

  static String _getGreeting(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Hallo daar! Dit is so goed om van jou te hoor. Waaroor dink jy vandag?'
            : 'Hello there. It is wonderful to hear from you. What has caught your imagination today?';
      case 'leo':
        return isAf
            ? 'Dag! Leo hier. Waarmee pak ons vandag dinge aan?'
            : 'Hey! Leo here. What are we tackling today?';
      case 'rex':
        return isAf
            ? 'Haai! Rex is hier en gereed vir aksie! Wat is die plan?'
            : 'Hey! Rex here and fired up. What are we making happen today?';
      case 'sal':
        return isAf
            ? 'Goeiedag. Rustig en gereed. Wat lê op jou hart?'
            : 'Hey. Nice and steady here. What is on your mind?';
      case 'eve':
      default:
        return isAf
            ? 'Hallo! Ek is Eve. Dit is so lekker om met jou te praat. Waarmee kan ek vandag help?'
            : 'Hello! I am Eve. It is really lovely to talk with you. What is on your mind today?';
    }
  }

  static String _getHowAreYou(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Dit gaan baie goed met my, dankie. Ek kyk na die wêreld met nuuskierigheid en warmte. Hoe voel dit aan jou kant?'
            : 'I am doing well, thank you. Feeling reflective and genuinely glad to connect with you. How are you holding up?';
      case 'leo':
        return isAf
            ? 'Kragtig en gefokus. Ons beweeg vorentoe. Hoe lyk jou dag tot dusver?'
            : 'Sharp, focused, and ready to get things done. How is your day shaping up?';
      case 'rex':
        return isAf
            ? 'Vol energie! Nooit \'n vervelige oomblik nie. En jy?'
            : 'Full of energy as always! Never a dull moment. How about you?';
      case 'sal':
        return isAf
            ? 'Goeie balans, lekker ontspanne. Hoop jou dag loop ook mooi gelyk.'
            : 'Grounded, peaceful, taking it in stride. Hope your day is treating you kindly.';
      case 'eve':
      default:
        return isAf
            ? 'Dit gaan uitstekend, dankie! Ek luister aandagtig en sien uit om te gesels.'
            : 'I am doing wonderfully, thank you! Attentive and right here with you. How are you doing?';
    }
  }

  static String _getAppearanceReply(String characterId, bool isAf) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Ek het donker, golwende hare en diep, nadenkende bruin oë met 'n kunstige en grasieuse voorkoms. Jy kan my foto bo-aan ons klets sien — tik gerus daarop om my van nader te bekyk!'
            : 'I have long dark wavy hair and thoughtful brown eyes with an artistic, expressive presence. You can see my portrait right above in our chat — tap it anytime to get a closer look!';
      case 'leo':
        return isAf
            ? 'Ek het netjiese donker hare, 'n skerp kaaklyn en dra 'n stylvolle donker baadjie met 'n gefokusde, selfversekerde styl. Tik gerus op my portret bo-aan as jy wil kyk.'
            : 'I have neatly styled dark hair, sharp features, and wear a tailored dark jacket with a focused, confident presence. Tap my portrait above if you would like to see!';
      case 'rex':
        return isAf
            ? 'Ek het 'n lewendige, energieke glimlag en 'n gemaklike, dinamiese sportiewe styl — altyd reg vir aksie. Tik op my prentjie bo om my van nader te sien!'
            : 'I sport an energetic grin, casual athletic style, and a high-energy vibe. You can tap my photo at the top of our chat to see the full portrait!';
      case 'sal':
        return isAf
            ? 'Ek het 'n netjiese natuurlike baard, vriendelike rustige oë en dra aardse, gemaklike klere met 'n ontspanne gevoel. Tik gerus op my avatar bo-aan om te sien.'
            : 'I have a neat natural beard, kind observant eyes, and warm, casual earth-toned attire with an easygoing presence. Tap my avatar above to see.';
      case 'eve':
      default:
        return isAf
            ? 'Ek het sagte golwende heuningbruin hare wat my gesig omraam, vonkelende hasel-groen oë en 'n sagte, warm glimlag met 'n fyn goue hangertjie. Jy kan my foto bo-aan die skerm sien — tik gerus daarop om my volgrootte portret te sien!'
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
            ? 'Ek luister met aandag na jou. Dit gee my baie om oor na te dink. Vertel my gerus meer daaroor.'
            : 'I am listening closely to what you shared. There is a lot of nuance there. Tell me more about your thoughts on it.';
      case 'leo':
        return isAf
            ? 'Ek hoor jou duidelik. Kom ons kyk na die feite en besluit op die beste pad vorentoe.'
            : 'I hear you. Let us look at the practical angle and find the most direct path forward.';
      case 'rex':
        return isAf
            ? 'Beslis! Ek hou van die rigting waarin ons beweeg. Kom ons kyk wat ons hieruit kan maak.'
            : 'Absolutely! I like where your head is at. Let us take this and run with it.';
      case 'sal':
        return isAf
            ? 'Goeie punt. Neem \'n oomblik om dit in te neem — dinge lyk dikwels duideliker met \'n bietjie asemruimte.'
            : 'Good perspective. Sometimes letting an idea breathe gives us the clearest view. What feels like the next right step?';
      case 'eve':
      default:
        return isAf
            ? 'Dankie dat jy dit met my deel. Ek is hier om te luister en saam met jou te dink. Wat sou jy volgende wou verken?'
            : 'Thank you for sharing that with me. I am right here listening and thinking alongside you. Where would you like to take this next?';
    }
  }
}
