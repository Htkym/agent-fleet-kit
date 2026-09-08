function eligible(years) {
  if (!Number.isInteger(years) || years < 0) {
    throw new RangeError('years must be a non-negative integer');
  }
  return years > 5;
}

module.exports = { eligible };
