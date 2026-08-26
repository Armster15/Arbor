import asyncio
from googletrans import Translator
from googletrans.models import Translated
import json


def _google_translate(text: str | list[str]) -> list[Translated]:
    translator = Translator(raise_exception=True)
    # HACKHACK: running async code in a sync function
    translated = asyncio.run(translator.translate(text))

    if isinstance(translated, Translated):
        return [translated]
    else:
        return translated


# HACKHACK: normally we'd get the romanization from the `pronunciation` attr on
# the `Translated` object but for some reason it returns None.
#
# In `extra_data`, there is a `translation` key that is an array of arrays of strings.
# The last string in the last array seems to contain the romanization. Therefore this
# recursively traverses the `translation` array to get the last string since we don't know
# exactly the number of dimensions of the array.
#
# I am unsure how stable relying on the fact that the romanization is the last string in the last array is,
# so this method should be treated as a hack.
def _get_romanization(result: Translated) -> str | None:
    def recursively_get_romanization(item: str | list[str] | None) -> str | None:
        if isinstance(item, list):
            return recursively_get_romanization(item[-1])
        elif isinstance(item, str):
            return item
        else:
            return None

    if result.extra_data:
        translations: list[str] | None = result.extra_data.get("translation")
        romanization = recursively_get_romanization(translations)

        # HACKHACK: sometimes the romanization text is a string of the form "it_en_2023q1.md".
        # In these cases, ignore the romanization and simply return None.
        if (
            romanization
            and romanization.endswith(".md")
            and romanization.find(" ") == -1
        ):
            return None

        return romanization

    else:
        return None


# Use this public method as the other two deal with googletrans internals
# which aren't JSON serializable
def translate(text: list[str]) -> str:
    result = _google_translate(text)

    translations: list[str] = []
    romanizations: list[str | None] = []

    for r in result:
        translations.append(r.text)

        romanization = _get_romanization(r)
        romanizations.append(romanization)

    payload = {
        "translations": translations,
        "romanizations": romanizations,
    }

    return json.dumps(payload, ensure_ascii=False)
