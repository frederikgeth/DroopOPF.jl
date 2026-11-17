# Qualify the loaded parser behavior: PowerIO 0.11.8 added a NOMV impedance
# factor that 0.11.7 did not apply and 0.11.9 removed. A version string alone
# also cannot distinguish local builds. Recheck after a library change because
# PowerIO.set_library! can select another library in the same process.
function _raw_transformer_basis_qualified()
    for (nom1, nom2) in ((0.,0.), (230.,115.), (110.,220.)), cw in 1:3, cz in 1:3
        wind1, wind2 = cw==2 ? (231.,107.8) : (1.05,.98)
        resistance = cz==3 ? 50000. : .01
        text = """
        0,200,33,0,0,50
        DroopOPF transformer basis qualification
        Synthetic two winding circuit
        1,'BUS1',220,3,1,1,1,1,0,1.1,.9,1.1,.9
        2,'BUS2',110,1,1,1,1,1,0,1.1,.9,1.1,.9
        0 / END OF BUS DATA, BEGIN LOAD DATA
        0 / END OF LOAD DATA, BEGIN FIXED SHUNT DATA
        0 / END OF FIXED SHUNT DATA, BEGIN GENERATOR DATA
        0 / END OF GENERATOR DATA, BEGIN BRANCH DATA
        0 / END OF BRANCH DATA, BEGIN TRANSFORMER DATA
        1,2,0,'1',$cw,$cz,1,0,0,2,'XF',1
        $resistance,.2,50
        $wind1,$nom1,5,100,110,120,0,0,1.1,.9,1.1,.9,33,0,0,0,0
        $wind2,$nom2
        0 / END OF TRANSFORMER DATA, BEGIN AREA DATA
        Q
        """
        module_ = try
            P.parse(P.PioModule{P.BalancedNetwork}, Vector{UInt8}(codeunits(text));
                name="transformer_basis_qualification.raw", format="psse")
        catch err
            err isa P.PowerIOError || rethrow()
            return false
        end
        isempty(module_.diagnostics) || return false
        length(module_.value.branches)==1 || return false
        branch = only(module_.value.branches)
        ratio1 = cw==2 ? 231/220 : cw==3 && nom1!=0 ? 1.05*nom1/220 : 1.05
        ratio2 = cw==2 ? 107.8/110 : cw==3 && nom2!=0 ? .98*nom2/110 : .98
        r = cz==3 ? .001 : .01
        x = cz==3 ? sqrt(.2^2-r^2) : .2
        scale = cz==1 ? 1. : 200/50
        isapprox(branch.resistance_pu, r*scale*ratio2^2; atol=1e-12,rtol=1e-10) || return false
        isapprox(branch.reactance_pu, x*scale*ratio2^2; atol=1e-12,rtol=1e-10) || return false
        isapprox(branch.effective_tap_ratio,ratio1/ratio2;atol=1e-12,rtol=1e-10) || return false
        isapprox(branch.phase_shift_degrees,5.;atol=1e-12,rtol=1e-10) || return false
    end
    true
end
