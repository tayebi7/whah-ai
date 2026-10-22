import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { connectorUrl, detectIntent, matchConnectors, matchSkills, subjectOf, urlsIn } from "../src/lib/intent";

const cases: [string, string][] = [
  ["ارسم قطة تجلس على القمر", "image"], ["صورة غروب فوق الصحراء", "image"], ["أنشئ شعار لمقهى", "image"], ["صمم بوستر لمعرض الكتاب", "image"],
  ["draw a red dragon", "image"], ["generate an image of a city at night", "image"], ["make me a logo for my bakery", "image"], ["dessine un chat", "image"], ["crée une affiche pour un concert", "image"],
  ["اصنع فيديو لمنتج عطر", "video"], ["فيديو قصير لسيارة في الصحراء", "video"], ["create a video of waves", "video"], ["fais une vidéo de la mer", "video"],
  ["اكتب لي قصة عن أرنب شجاع", "story"], ["write a story about a lost robot", "story"], ["raconte... écris une histoire de pirates", "story"],
  ["اكتب كتاب عن الطبخ الجزائري", "book"], ["write a book about astronomy", "book"], ["écris un livre sur la photographie", "book"],
  ["كيف أرسم وجه؟", "chat"], ["how to make a video go viral", "chat"], ["ما هي عاصمة الجزائر", "chat"], ["what is a logo", "chat"], ["مرحبا", "chat"], ["explain how images are compressed", "chat"],
  ["أريد صورة لجبل", "image"],
];
describe("intent", () => {
  for (const [p, want] of cases) it(`${p} → ${want}`, () => assert.equal(detectIntent(p).intent, want));
  it("extracts the subject", () => {
    assert.equal(subjectOf("ارسم صورة لقطة في الفضاء"), "قطة في الفضاء");
    assert.equal(subjectOf("generate an image of a castle"), "a castle");
    assert.equal(subjectOf("draw a cat"), "draw a cat");
  });
  it("matches skills and connectors by keyword", () => {
    const sk = [{ id: "1", name: "n", instruction: "i", keywords: "ترجم, translate", enabled: true }, { id: "2", name: "o", instruction: "i", keywords: "code", enabled: false }];
    assert.equal(matchSkills(sk, "Please translate this").length, 1);
    assert.equal(matchSkills(sk, "code").length, 0);
    assert.equal(matchSkills(sk, "x", ["1"]).length, 1);
    const cs = [{ id: "w", name: "wiki", urlTemplate: "https://ar.wikipedia.org/w/api.php?search={query}", headers: "", keywords: "ويكيبيديا,wikipedia", enabled: true }];
    assert.equal(matchConnectors(cs, "wikipedia: Algeria").length, 1);
    assert.match(connectorUrl(cs[0], "a b"), /search=a%20b/);
    assert.deepEqual(urlsIn("اقرأ https://a.com/x و http://no.com"), ["https://a.com/x"]);
  });
});
