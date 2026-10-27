import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config/api_key.dart';

class GeminiService {
  static const _url =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent';

  // FIXED: parseExpense previously referenced two dead-code getters,
  // `financeContext` and `question`, that always returned null instead of
  // using its actual `input` and `categories` parameters. This meant the
  // prompt sent to Gemini always said "null" for both the finance context
  // and the question, so the AI had nothing real to parse. Now it builds
  // the prompt from what was actually passed in, and asks Gemini to
  // extract an amount and category from a natural-language expense
  // description (e.g. "spent 200 on lunch" -> {"amount": 200, "category":
  // "Food"}), returning that as a parsed map for quick-add style entry.
  static Future<Map<String, dynamic>?> parseExpense(String input, List<String> categories) async {
    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'x-goog-api-key': ApiKeys.geminiApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': 'Parse this expense description into a structured transaction: "$input"\n\n'
                      'Pick the closest matching category from this exact list: ${categories.join(', ')}.\n\n'
                      'Reply with ONLY a raw JSON object, no markdown formatting, no code fences, no extra '
                      'text, in exactly this shape:\n'
                      '{"amount": <number>, "category": "<one of the categories above>", "note": "<short note>"}\n\n'
                      'If you cannot confidently determine an amount, set "amount" to null. If no category '
                      'clearly fits, use "Other".'
                }
              ]
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(clean) as Map<String, dynamic>;
      }
    } catch (e) {
      // fall through to null below
    }
    return null;
  }

  static Future<String> askQuestion(String question, String financeContext) async {
    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'x-goog-api-key': ApiKeys.geminiApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': 'Here is the user\'s financial data for this month:\n$financeContext\n\n'
                      'Answer this question based only on the data above: "$question"\n\n'
                      'Reply in plain text, 2-4 sentences, friendly and direct. If the data doesn\'t '
                      'contain enough information to answer, say so plainly instead of guessing.'
                }
              ]
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        return text.trim();
      }
      return 'Something went wrong reaching the AI (code ${response.statusCode}): ${response.body}';
    } catch (e) {
      return 'Something went wrong reaching the AI. Please try again.';
    }
  }
}