include("src/PeaceFounderAdmin.jl")

import HTTP
import PeaceFounder


try
    global service = HTTP.serve!(PeaceFounder.Service.ROUTER, "0.0.0.0", 4584)
    PeaceFounderAdmin.serve(port=3221)
finally 
    close(service)
end
