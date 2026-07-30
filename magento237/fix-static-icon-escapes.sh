#!/bin/sh

set -eu

# Magento 2.3's legacy LESS compiler can preserve both backslashes from icon
# variables such as '\\e605'. CSS then treats the value as visible text instead
# of a private-use glyph. Normalize deployed CSS to one backslash per glyph.
find pub/static/frontend pub/static/adminhtml \
    -type f -name '*.css' \
    -exec sed -i 's/\\\\e/\\e/g' {} +
