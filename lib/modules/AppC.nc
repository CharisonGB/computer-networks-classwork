configuration AppC
{
	provides interface App;
}

implementation
{
	components AppP;
	App = AppP;
	
	components CommandHandlerC;
    AppP.CommandHandler -> CommandHandlerC;
	
	components TransportC;
	AppP.Transport -> TransportC;
	
	components new TimerMilliC() as ConnTimer;
	AppP.ConnectDelay -> ConnTimer;
	
	components new TimerMilliC() as WriteTimer, new TimerMilliC() as ReadTimer;
	AppP.WriteDelay -> WriteTimer;
	AppP.ReadDelay -> ReadTimer;
	
	components RandomC;
	AppP.Random -> RandomC;
}