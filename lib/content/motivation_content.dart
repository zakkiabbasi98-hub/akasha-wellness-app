import '../data/models/mind_models.dart';

/// The built-in supportive message library.
///
/// 104 original messages across the eight requested categories. Written to be
/// gentle: no guilt, no pressure, no "you must". Seeded into the database on
/// first launch so they work fully offline and can be favourited, filtered and
/// counted for anti-repetition rotation.
const Map<MotivationCategory, List<String>> kMotivationSeeds = {
  MotivationCategory.confidence: [
    'Akasha, you are far more capable than the story in your head says.',
    'You have already survived every hard day you thought you could not.',
    'Your voice deserves to be heard, even when it shakes a little.',
    'You do not need to be perfect to be worthy of good things.',
    'The way you care for others is a strength. Let some of it land on you.',
    'You bring something to the room that no one else can.',
    'Being unsure does not make you less. It makes you human.',
    'You are allowed to take up space, softly and fully.',
    'What you do matters, even on the days it feels invisible.',
    'You have grown in ways nobody clapped for. I see it.',
    'Your kindness is not weakness. It is quiet courage.',
    'You are becoming someone you will be proud to be.',
    'Trust the version of you that keeps showing up.',
    'You do not have to earn your place in your own life.',
  ],
  MotivationCategory.selfLove: [
    'Give yourself the kindness you give to everyone else.',
    'You are allowed to rest without feeling guilty.',
    'You deserve care that does not have to be asked for twice.',
    'Speak to yourself the way you would speak to someone you love.',
    'Your body is not a project. It is a home.',
    'You do not need to fix yourself to be loved.',
    'Making yourself a priority is not selfish. It is maintenance.',
    'You are allowed to want things for yourself.',
    'Be proud of the small things. They are not small.',
    'You are worth the effort it takes to feel better.',
    'Notice one thing you did today that was kind to you. Hold onto it.',
    'You are not too much. You were just around people with small cups.',
    'Your softness is a gift, not a flaw.',
    'Drink some water. That counts as love too.',
    'Forgive yourself for the days you were only surviving.',
  ],
  MotivationCategory.overthinking: [
    'Akasha, you do not need to figure out everything today.',
    'Not every conversation needs to be analysed.',
    'Sometimes the best thing you can do is stop thinking and start breathing.',
    'A thought is not a fact. Let it pass through like weather.',
    'You can care about someone and still stop decoding their every word.',
    'If you are replaying it, you probably cared. That is enough.',
    'You cannot think your way into certainty about another person.',
    'The version of the conversation in your head is only one version.',
    'Give this thought permission to wait until tomorrow.',
    'Not every silence is a message about you.',
    'You are allowed to let a thought rest without solving it.',
    'Breathe in for four. Out for six. The looping can wait.',
    'Ask: is this a problem, or is this a feeling?',
    'Replaying it again will not give you a different ending today.',
    'You can put the thought down without throwing it away.',
    'It is okay to not know how someone meant it.',
    'Your mind is trying to protect you. Thank it, then gently move on.',
    'Three slow breaths are a full sentence to your nervous system.',
  ],
  MotivationCategory.productivity: [
    'One small step is still a step. Direction matters more than speed.',
    'You do not have to do it all. Pick the next single thing.',
    'A ten-minute start beats a perfect plan you never begin.',
    'Rest is part of the work, not a break from it.',
    'You are allowed to do enough instead of everything.',
    'Done and gentle beats perfect and exhausted.',
    'Today can be a small day. Small days still count.',
    'Make the list shorter on purpose. That is a skill.',
    'If it feels heavy, make it smaller until it moves.',
    'Your worth is not measured by your output today.',
    'Start where you are, with what you have, for as long as you can.',
    'A little progress repeated becomes a life that changed.',
    'Take the break before your body makes the decision for you.',
    'You can be proud of a quiet, unproductive day too.',
  ],
  MotivationCategory.calmness: [
    'You do not have to hold everything tightly to keep it.',
    'Nothing here needs to be solved in the next five minutes.',
    'Let your shoulders drop. Unclench your jaw. That is the whole task.',
    'Slow is allowed. Slow is often wiser.',
    'The day is not a race, and you are not behind.',
    'Your calm is not something you lost. It is something you return to.',
    'Place your hand on your heart. It has been working all day for you.',
    'Breathe out longer than you breathe in. That is the anchor.',
    'You are safe in this ordinary moment.',
    'Notice five things you can see. Come back to the room.',
    'It is okay for today to be unremarkable and safe.',
    'Peace does not require everything to be resolved.',
    'Step outside for a minute. Your mind likes open air.',
    'You can be calm and still have unanswered questions.',
  ],
  MotivationCategory.gratitude: [
    'Three small things went right today. They are allowed to count.',
    'Gratitude is not pretending the hard parts are not there.',
    'Notice something warm: a drink, a message, a patch of sunlight.',
    'You have been given some soft moments. Let one land.',
    'Thank the person who crossed your mind today. Silently is fine.',
    'Your life has small good things in it, even now.',
    'Today, one thing was easier than it could have been. That was grace.',
    'Write down one thing you want to remember about today.',
    'Being grateful for small things is not settling. It is noticing.',
    'There was a moment today you felt okay. Keep it.',
    'Someone was kind to you recently. Let yourself feel it again.',
    'You are allowed to be thankful and tired at the same time.',
  ],
  MotivationCategory.courage: [
    'You do not have to be fearless to do the brave thing.',
    'Saying the honest sentence is scary and worth it.',
    'You can ask for what you need. The worst answer is still information.',
    'The version of you that tries is braver than the one that waits.',
    'You are allowed to change your mind out loud.',
    'Boundaries are not walls. They are doorways with handles on your side.',
    'It takes courage to rest in a world that rewards exhaustion.',
    'You can take the small risk today. You can also take it tomorrow.',
    'You are allowed to put your own needs in the same room as everyone else\'s.',
    'Ask the question. Send the message. You will handle the answer.',
    'You have done harder things than this with less support.',
    'Showing up scared is the whole definition of brave.',
  ],
  MotivationCategory.growth: [
    'Your potential is bigger than your fears.',
    'You are not behind. You are on a different timeline.',
    'One difficult day does not define your entire life.',
    'Growth is rarely loud. It looks like small choices, repeated.',
    'You are allowed to outgrow things that once fit you.',
    'Every version of you was doing their best with what they had.',
    'It is fine to be a beginner at something you care about.',
    'You do not have to become someone else to become better.',
    'The seasons in your life are allowed to change slowly.',
    'You can start again at any hour of any day.',
    'The person you are becoming is being built by quiet days like today.',
    'You do not need permission to want more for yourself.',
    'Healing is not linear. Neither is progress. Both are still real.',
    'You are learning. That is the whole point.',
  ],
};

/// Voice lines spoken with water reminders — rotated so it never feels canned.
const List<String> kWaterVoiceLines = [
  "Hey Akasha! It's time to drink some water.",
  'Dear Akasha, take a little break and hydrate yourself.',
  "Your body deserves care. Don't forget your water!",
  'One little glass of water can be a beautiful step toward taking care of yourself.',
  'A gentle reminder, Akasha — a sip of water would be lovely right now.',
  'Hey you. Water first, then everything else.',
  'Your future self will thank you for this glass.',
  'Little sip, big kindness. Time for water.',
  'Akasha, hydration is a form of self-respect. Go on, love.',
  'Take a breath, take a sip. You are doing beautifully.',
];

/// Notification copy for water reminders (title + body pairs).
const List<List<String>> kWaterNotificationCopy = [
  ['Time for water, Akasha ♡', 'A small glass now keeps your energy kind.'],
  ['A gentle water moment', 'Pause for ten seconds. Sip. Breathe. Continue.'],
  ['Hydration check-in', 'Your body is quietly asking for a little water.'],
  ['Akasha, water break 💧', 'You have done enough thinking. Time for a drink.'],
  ['Little sip, big kindness', 'Every glass is you taking care of yourself.'],
  ['Your water is waiting', 'One glass, that is all. Then back to your day.'],
];

/// Medicine notification copy — deliberately calmer and message-like.
const List<List<String>> kMedicineNotificationCopy = [
  [
    'A little medicine reminder',
    'Hello Akasha! A little reminder about your scheduled medicine. Please check your prescription and take it if it is due.',
  ],
  [
    'Medicine time, gently',
    'Your scheduled medicine is due. Only take it if it matches your prescription.',
  ],
  [
    'Checking in about your medicine',
    'This is your reminder for the dose you scheduled. No pressure — just keeping you company.',
  ],
];

/// Love-note seeds are inserted as real, editable rows (see
/// LoveNoteRepository.seedIfEmpty) rather than drawn in the UI.

/// Daily self-care prompts shown on the dashboard, one per day.
const List<String> kSelfCarePrompts = [
  'Unclench your jaw and drop your shoulders. That is it.',
  'Drink a full glass of water slowly, without your phone.',
  'Step outside for two minutes of real air.',
  'Write down one thing that went right today.',
  'Put your phone down and breathe for ten slow breaths.',
  'Stretch your neck gently, side to side.',
  'Say one kind sentence to yourself out loud.',
  'Tidy one small surface. Just one.',
  'Text someone you miss, just to say hi.',
  'Sit somewhere comfortable and do absolutely nothing for five minutes.',
  'Eat something slowly today, without rushing.',
  'Close your eyes and let your face relax completely.',
  'Notice five things you can see right now.',
  'Give yourself permission to do less this evening.',
];

/// Crisis-support guidance. Shown when the AI companion detects language
/// suggesting immediate danger, and always available in Privacy & safety.
/// Region-agnostic on purpose: local services change, so we point to
/// directories rather than hard-coding numbers that may be wrong.
const String kCrisisSupportMessage =
    'If you are in immediate danger or thinking about harming yourself, please '
    'reach out to a real person right now — a trusted family member, a friend, or '
    'a local emergency number. Akasha is a wellness companion, not a crisis '
    'service, and it cannot contact anyone for you. If you can, tell someone near '
    'you how you are feeling. You deserve support from a human being.';
