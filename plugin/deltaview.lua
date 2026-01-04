-- todo; figure out how users can initialize with custom config, and have the require below use that config instead of blank config
-- plugin/ overrides anything before, so whatever code is in here is the highest priority config wise. That might be a problem.
require('deltaview').setup({
    use_nerdfonts = true
})
