import 'package:flutter_test/flutter_test.dart';
import 'package:whah_ai/intent.dart';

void main() {
  Intent d(String t, {bool img = false, bool vid = false, List<String> ext = const []}) =>
      IntentDetector.detect(t, hasImages: img, hasVideo: vid, fileExts: ext).intent;

  test('image generation', () {
    expect(d('ولّد لي صورة لقطة على القمر'), Intent.imageGen);
    expect(d('generate an image of a red car'), Intent.imageGen);
    expect(d('ارسم شعار لمتجر قهوة'), Intent.imageGen);
  });
  test('video generation', () {
    expect(d('أنشئ فيديو قصير لغروب الشمس'), Intent.videoGen);
  });
  test('not generation', () {
    expect(d('اكتب لي سيناريو فيديو عن السفر'), isNot(Intent.videoGen));
    expect(d('حلل هذه الصورة', img: true), Intent.vision);
  });
  test('finance', () {
    expect(d('راجع هذه الفاتورة واحسب الضريبة'), Intent.finance);
    expect(d('check this invoice total and VAT'), Intent.finance);
  });
  test('social', () {
    expect(d('اكتب كابشن لريلز على انستغرام مع هاشتاقات'), Intent.social);
  });
  test('problem', () {
    expect(d('التطبيق لا يعمل ويظهر خطأ exception'), Intent.problem);
  });
  test('chat', () {
    expect(d('ما عاصمة الجزائر؟'), Intent.chat);
  });
  test('data attachment', () {
    expect(d('لخص', ext: ['xlsx']), isNot(Intent.chat));
  });
}
