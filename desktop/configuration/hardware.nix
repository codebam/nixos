_:

{
  hardware = {
    amdgpu = {
      overdrive = {
        enable = true;
        ppfeaturemask = "0xffffffff";
      };
    };
    # hardware.fancontrol was carrying a full disabled pwmconfig dump; recover it
    # from git history if the nct6798 curves are ever wanted again.
  };
}
