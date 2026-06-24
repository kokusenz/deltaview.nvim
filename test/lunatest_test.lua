local lunatest = require('lunatest')

local test_equality = function()
    lunatest.assert_equal(6, 2 * 3)
end

lunatest.run()
